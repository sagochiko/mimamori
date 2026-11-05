// "毎朝の笑顔" (docs/design.md, task 13 in docs/plan.md). Anyone in the family sends a smile, a
// one-line reply, or both; everyone in the family sees them all. Photos sit in R2 under the family's
// prefix and are served only through GET /smiles/{id}/photo to members of the same family (the R2
// binding cannot make presigned URLs, per Cloudflare's "Presigned URLs" page). When the
// protected member's smile has not come by the family's hour (JST), the family members get one quiet
// notice that day; the family's own smiles do not count, since this is her daily check.
//
// Photos never go to Claude or Managed Agents, and neither photos nor notes are logged.

import { requireMember, type Member } from "./auth";
import { ExternalBudget } from "./budget";
import { familyR2Prefix } from "./families";
import { HttpError, json, readJson } from "./http";
import { sendPush } from "./push";
import { jstDate, jstMidnight } from "./time";

/** Bytes of one photo. The app sends about 640 pixels wide, well under this. */
export const MAX_PHOTO_BYTES = 500_000;
/**
 * The words a one-line reply can be. No free text is carried from one member to another: the author
 * chose set words on 2026-11-05, for the reason the case relays were taken out (docs/design.md,
 * "毎朝の笑顔"). The app has the same list (ios/Core, SmileNote); a note is sent as its id, and the
 * words themselves are accepted too.
 */
export const SMILE_NOTES = [
  { id: "good-morning", text: "おはよう" },
  { id: "nice-smile", text: "いい笑顔" },
  { id: "thanks", text: "ありがとう" },
  { id: "doing-fine", text: "元気だよ" },
  { id: "see-you", text: "またね" },
] as const;
/** What GET /smiles returns: the last week, at most this many. */
const LIST_DAYS = 7;
const LIST_LIMIT = 50;
export const DEFAULT_DEADLINE_HOUR = 9;
export const DEADLINE_HOURS = { min: 5, max: 12 } as const;
const UNKNOWN_NAME = "家族";
/** Families looked at per tick; more wait for the next tick. */
const MISSED_PER_TICK = 20;

interface SmileRow {
  id: string;
  member_id: string;
  display_name: string | null;
  role: string | null;
  score: number | null;
  note: string | null;
  r2_key: string;
  created_at: number;
}

function toJson(row: SmileRow) {
  return {
    id: row.id,
    memberId: row.member_id,
    displayName: row.display_name ?? UNKNOWN_NAME,
    role: row.role,
    score: row.score,
    note: row.note,
    hasPhoto: row.r2_key !== "",
    createdAt: new Date(row.created_at).toISOString(),
  };
}

function decodeBase64(text: string): Uint8Array {
  // Uint8Array.fromBase64 decodes without a JavaScript loop, which keeps the CPU time down.
  const native = (Uint8Array as unknown as { fromBase64?: (s: string) => Uint8Array }).fromBase64;
  try {
    if (native) return native(text);
    return Uint8Array.from(atob(text), (c) => c.charCodeAt(0));
  } catch {
    throw new HttpError(400, "photo_invalid");
  }
}

function readPhoto(value: unknown): Uint8Array | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== "string" || value === "") throw new HttpError(400, "photo_invalid");
  // Base64 is 4 characters per 3 bytes; refuse before decoding something far too large.
  if (value.length > Math.ceil(MAX_PHOTO_BYTES / 3) * 4 + 4) throw new HttpError(413, "photo_too_large");
  const bytes = decodeBase64(value);
  if (bytes.length > MAX_PHOTO_BYTES) throw new HttpError(413, "photo_too_large");
  // JPEG starts with the SOI marker FF D8 FF.
  if (bytes.length < 3 || bytes[0] !== 0xff || bytes[1] !== 0xd8 || bytes[2] !== 0xff) {
    throw new HttpError(400, "photo_invalid");
  }
  return bytes;
}

function readNote(value: unknown): string | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== "string") throw new HttpError(400, "note_invalid");
  const note = value.trim();
  if (note === "") return null;
  const set = SMILE_NOTES.find((n) => n.id === note || n.text === note);
  if (!set) throw new HttpError(400, "note_not_allowed");
  return set.text;
}

function readScore(value: unknown): number | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0 || value > 1) {
    throw new HttpError(400, "score_invalid");
  }
  return value;
}

/** POST /smiles: `{ photo?: base64 JPEG, score?: 0..1, note?: string }`, at least a photo or a note. */
export async function postSmile(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
  const me = await requireMember(request, env);
  const body = await readJson(request);
  const note = readNote(body.note);
  const score = readScore(body.score);
  const photo = readPhoto(body.photo);
  if (!photo && !note) throw new HttpError(400, "smile_empty");

  const id = crypto.randomUUID();
  const now = Date.now();
  const r2Key = photo ? `${familyR2Prefix(me.familyId)}smiles/${id}.jpg` : "";
  if (photo) await env.PHOTOS.put(r2Key, photo, { httpMetadata: { contentType: "image/jpeg" } });
  try {
    await env.DB.prepare(
      "INSERT INTO smiles (id, family_id, member_id, r2_key, score, note, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
    )
      .bind(id, me.familyId, me.id, r2Key, photo ? score : null, note, now)
      .run();
  } catch (error) {
    // A photo without its row would be missed by the 30-day cleanup, which reads the rows.
    if (photo) await env.PHOTOS.delete(r2Key);
    throw error;
  }

  ctx.waitUntil(tellOthers(env, me, photo !== null, note));

  return json(
    toJson({
      id,
      member_id: me.id,
      display_name: me.displayName,
      role: me.role,
      score: photo ? score : null,
      note,
      r2_key: r2Key,
      created_at: now,
    }),
    201,
  );
}

/** Everyone in the family but the sender, quietly. The note is shown as it was written. */
async function tellOthers(env: Env, me: Member, hasPhoto: boolean, note: string | null): Promise<void> {
  try {
    const others = await env.DB.prepare("SELECT id FROM members WHERE family_id = ? AND id != ?")
      .bind(me.familyId, me.id)
      .all<{ id: string }>();
    const ids = others.results.map((r) => r.id);
    if (ids.length === 0) return;
    const body = note ? `${me.displayName}「${note}」` : `${me.displayName}の笑顔`;
    await sendPush(
      env,
      ids,
      { body, quiet: true, threadId: "smiles", data: { kind: "smile", hasPhoto } },
      new ExternalBudget(),
    );
  } catch (error) {
    console.error("smile push failed", error instanceof Error ? error.name : typeof error);
  }
}

async function deadlineHour(env: Env, familyId: string): Promise<number> {
  const row = await env.DB.prepare("SELECT smile_deadline_hour AS hour FROM families WHERE id = ?")
    .bind(familyId)
    .first<{ hour: number }>();
  return row?.hour ?? DEFAULT_DEADLINE_HOUR;
}

/** GET /smiles: `{ smiles: [...], deadlineHour }`, the family's last week, newest first. */
export async function listSmiles(request: Request, env: Env): Promise<Response> {
  const me = await requireMember(request, env);
  const rows = await env.DB.prepare(
    `SELECT s.id, s.member_id, m.display_name, m.role, s.score, s.note, s.r2_key, s.created_at
       FROM smiles s LEFT JOIN members m ON m.id = s.member_id
      WHERE s.family_id = ? AND s.created_at >= ?
      ORDER BY s.created_at DESC, s.rowid DESC
      LIMIT ?`,
  )
    .bind(me.familyId, Date.now() - LIST_DAYS * 24 * 3600_000, LIST_LIMIT)
    .all<SmileRow>();
  return json({ smiles: rows.results.map(toJson), deadlineHour: await deadlineHour(env, me.familyId) });
}

/** GET /smiles/{id}/photo: the JPEG, only to members of the smile's family (403 to others). */
export async function smilePhoto(request: Request, env: Env, id: string): Promise<Response> {
  const me = await requireMember(request, env);
  const row = await env.DB.prepare("SELECT family_id, r2_key FROM smiles WHERE id = ?")
    .bind(id)
    .first<{ family_id: string; r2_key: string }>();
  if (!row) throw new HttpError(404, "not_found");
  if (row.family_id !== me.familyId) throw new HttpError(403, "not_your_family");
  if (row.r2_key === "") throw new HttpError(404, "no_photo");
  const object = await env.PHOTOS.get(row.r2_key);
  if (!object) throw new HttpError(404, "no_photo");
  return new Response(object.body, {
    headers: {
      "Content-Type": "image/jpeg",
      // A photo never changes, but it must not sit in a shared cache.
      "Cache-Control": "private, max-age=86400",
    },
  });
}

/** PUT /families/me/smile-deadline: `{ hour }`, 5 to 12 (JST). Family members only. */
export async function setSmileDeadline(request: Request, env: Env): Promise<Response> {
  const me = await requireMember(request, env);
  if (me.role !== "family") throw new HttpError(403, "family_only");
  const { hour } = await readJson(request);
  if (typeof hour !== "number" || !Number.isInteger(hour) || hour < DEADLINE_HOURS.min || hour > DEADLINE_HOURS.max) {
    throw new HttpError(400, "hour_invalid");
  }
  await env.DB.prepare("UPDATE families SET smile_deadline_hour = ? WHERE id = ?").bind(hour, me.familyId).run();
  return json({ deadlineHour: hour });
}

/**
 * Every tick (src/cron.ts). A family is due when today's hour (JST) has passed, it was not told
 * today, a protected member joined before today's hour, and no smile photo of a protected member
 * came since 00:00 JST (a set word alone does not count, as on her family's screen). The day is
 * claimed before sending, so a second tick never sends again; if the budget could not cover the
 * devices, the claim goes back and a later tick tries again.
 */
export async function notifyMissedSmiles(env: Env, now: number, budget: ExternalBudget): Promise<void> {
  const today = jstDate(now);
  const midnight = jstMidnight(now);
  const due = await env.DB.prepare(
    `SELECT f.id, f.smile_missed_notified_on AS told_on,
            (SELECT p.display_name FROM members p
              WHERE p.family_id = f.id AND p.role = 'protected' ORDER BY p.created_at LIMIT 1) AS name
       FROM families f
      WHERE ? + f.smile_deadline_hour * 3600000 <= ?
        AND (f.smile_missed_notified_on IS NULL OR f.smile_missed_notified_on != ?)
        AND EXISTS (SELECT 1 FROM members p WHERE p.family_id = f.id AND p.role = 'protected'
                     AND p.created_at < ? + f.smile_deadline_hour * 3600000)
        AND NOT EXISTS (SELECT 1 FROM smiles s JOIN members p ON p.id = s.member_id
                         WHERE s.family_id = f.id AND p.role = 'protected' AND s.r2_key != ''
                           AND s.created_at >= ?)
      LIMIT ?`,
  )
    .bind(midnight, now, today, midnight, midnight, MISSED_PER_TICK)
    .all<{ id: string; told_on: string | null; name: string | null }>();

  for (const family of due.results) {
    const claim = await env.DB.prepare(
      `UPDATE families SET smile_missed_notified_on = ?
        WHERE id = ? AND (smile_missed_notified_on IS NULL OR smile_missed_notified_on != ?)`,
    )
      .bind(today, family.id, today)
      .run();
    if (claim.meta.changes !== 1) continue;

    const members = await env.DB.prepare("SELECT id FROM members WHERE family_id = ? AND role = 'family'")
      .bind(family.id)
      .all<{ id: string }>();
    const results = await sendPush(
      env,
      members.results.map((m) => m.id),
      { body: `今朝は${family.name ?? UNKNOWN_NAME}の笑顔がまだです`, quiet: true, threadId: "smiles" },
      budget,
    );
    if (results.some((r) => r.status === "skipped" && r.reason === "no_budget")) {
      await env.DB.prepare(
        "UPDATE families SET smile_missed_notified_on = ? WHERE id = ? AND smile_missed_notified_on = ?",
      )
        .bind(family.told_on, family.id, today)
        .run();
    }
  }
}
