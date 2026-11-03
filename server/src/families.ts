// Families, invites, and members.

import {
  hashDeviceKey,
  newDeviceKey,
  newFamilyToken,
  newInviteCode,
  requireMember,
  type Role,
} from "./auth";
import { deleteAgentSession } from "./agents";
import { revokeGmailGrant } from "./gmail";
import { errorResponse, HttpError, json, noContent, readJson } from "./http";
import { sendPush } from "./push";

export const INVITE_LIFETIME_MS = 24 * 3600_000;
const DISPLAY_NAME_MAX = 40;

function displayName(value: unknown, required: boolean): string {
  if (value === undefined && !required) return "";
  if (typeof value !== "string") throw new HttpError(400, "display_name_invalid");
  const name = value.trim();
  if ((required && name === "") || name.length > DISPLAY_NAME_MAX) {
    throw new HttpError(400, "display_name_invalid");
  }
  return name;
}

function role(value: unknown): Role {
  if (value === "protected" || value === "family") return value;
  throw new HttpError(400, "role_invalid");
}

async function insertMember(
  env: Env,
  familyId: string,
  memberRole: Role,
  name: string,
): Promise<{ memberId: string; deviceKey: string; statement: D1PreparedStatement }> {
  const memberId = crypto.randomUUID();
  const deviceKey = newDeviceKey();
  const statement = env.DB.prepare(
    "INSERT INTO members (id, family_id, role, display_name, device_key_hash, created_at) VALUES (?, ?, ?, ?, ?, ?)",
  ).bind(memberId, familyId, memberRole, name, await hashDeviceKey(deviceKey), Date.now());
  return { memberId, deviceKey, statement };
}

/** POST /families: the caller becomes the first member, with the family role. */
export async function createFamily(request: Request, env: Env): Promise<Response> {
  const body = await readJson(request);
  const name = displayName(body.display_name, false);
  const familyId = crypto.randomUUID();
  const familyToken = newFamilyToken();
  const member = await insertMember(env, familyId, "family", name);
  await env.DB.batch([
    env.DB.prepare("INSERT INTO families (id, token, created_at) VALUES (?, ?, ?)").bind(
      familyId,
      familyToken,
      Date.now(),
    ),
    member.statement,
  ]);
  return json(
    { familyId, memberId: member.memberId, deviceKey: member.deviceKey, familyToken, role: "family" },
    201,
  );
}

/** POST /invites: a six-digit code for the caller's family, valid for 24 hours. */
export async function createInvite(request: Request, env: Env): Promise<Response> {
  const me = await requireMember(request, env);
  const now = Date.now();
  const expiresAt = now + INVITE_LIFETIME_MS;
  for (let attempt = 0; attempt < 5; attempt++) {
    const code = newInviteCode();
    // A code that was used or has expired can be handed out again.
    const [, inserted] = await env.DB.batch([
      env.DB.prepare(
        "DELETE FROM invites WHERE code = ? AND (used_at IS NOT NULL OR expires_at <= ?)",
      ).bind(code, now),
      env.DB.prepare(
        "INSERT INTO invites (code, family_id, expires_at) VALUES (?, ?, ?) ON CONFLICT (code) DO NOTHING",
      ).bind(code, me.familyId, expiresAt),
    ]);
    if ((inserted?.meta.changes ?? 0) === 1) {
      return json({ code, expiresAt: new Date(expiresAt).toISOString() }, 201);
    }
  }
  throw new HttpError(503, "invite_code_busy");
}

/**
 * POST /invites/{code}/join with { role, display_name }. Returns the new device key and the family
 * token (the protected person's phone puts it in the SMS and DNS addresses).
 * Unknown, used, and expired codes all answer 404 so the reply does not tell which codes exist,
 * and each client address gets only a few tries a minute, so six digits cannot be walked through.
 * Everyone already in the family is told who joined.
 */
export async function joinInvite(
  request: Request,
  env: Env,
  ctx: ExecutionContext,
  code: string,
): Promise<Response> {
  const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
  const { success } = await env.JOIN_LIMITER.limit({ key: `join:${ip}` });
  if (!success) throw new HttpError(429, "too_many_attempts");

  const body = await readJson(request);
  const memberRole = role(body.role);
  const name = displayName(body.display_name, true);
  if (!/^\d{6}$/.test(code)) throw new HttpError(404, "invite_unavailable");

  const now = Date.now();
  // One statement claims the code, so of two simultaneous joins only one gets a row back.
  const claimed = await env.DB.prepare(
    "UPDATE invites SET used_at = ? WHERE code = ? AND used_at IS NULL AND expires_at > ? RETURNING family_id",
  )
    .bind(now, code, now)
    .first<{ family_id: string }>();
  if (!claimed) throw new HttpError(404, "invite_unavailable");

  const family = await env.DB.prepare("SELECT token FROM families WHERE id = ?")
    .bind(claimed.family_id)
    .first<{ token: string }>();
  if (!family) throw new HttpError(404, "invite_unavailable");
  const others = await env.DB.prepare("SELECT id FROM members WHERE family_id = ?")
    .bind(claimed.family_id)
    .all<{ id: string }>();

  const member = await insertMember(env, claimed.family_id, memberRole, name);
  await member.statement.run();

  // After the response; a failed push must not undo the join.
  ctx.waitUntil(
    sendPush(env, others.results.map((r) => r.id), { body: `${name}が入りました` }).then(
      () => undefined,
      () => undefined,
    ),
  );
  return json(
    {
      familyId: claimed.family_id,
      memberId: member.memberId,
      deviceKey: member.deviceKey,
      familyToken: family.token,
      role: memberRole,
    },
    201,
  );
}

/** PUT /members/me/apns with { token, env }. env is "sandbox" or "production" (the default). */
export async function registerApns(request: Request, env: Env): Promise<Response> {
  const me = await requireMember(request, env);
  const body = await readJson(request);
  const token = body.token;
  if (typeof token !== "string" || !/^[0-9a-fA-F]{32,200}$/.test(token)) {
    throw new HttpError(400, "apns_token_invalid");
  }
  const apnsEnv = body.env ?? "production";
  if (apnsEnv !== "sandbox" && apnsEnv !== "production") throw new HttpError(400, "apns_env_invalid");
  await env.DB.prepare("UPDATE members SET apns_token = ?, apns_env = ? WHERE id = ?")
    .bind(token.toLowerCase(), apnsEnv, me.id)
    .run();
  return noContent();
}

/**
 * DELETE /members/{id}: leave the family. Only the member themself (or "me").
 * The row goes away, so the device key answers 401 from the next call.
 */
export async function leaveFamily(request: Request, env: Env, memberId: string): Promise<Response> {
  const me = await requireMember(request, env);
  if (memberId !== "me" && memberId !== me.id) throw new HttpError(403, "only_self");
  await env.DB.prepare("DELETE FROM members WHERE id = ?").bind(me.id).run();
  return noContent();
}

/** R2 keys of a family's objects start with this, so a prefix listing finds every photo. */
export function familyR2Prefix(familyId: string): string {
  return `${familyId}/`;
}

async function deleteFamilyPhotos(env: Env, familyId: string): Promise<void> {
  const rows = await env.DB.prepare("SELECT r2_key FROM smiles WHERE family_id = ?")
    .bind(familyId)
    .all<{ r2_key: string }>();
  const keys = new Set(rows.results.map((r) => r.r2_key));
  let cursor: string | undefined;
  do {
    const page = await env.PHOTOS.list({ prefix: familyR2Prefix(familyId), cursor });
    for (const object of page.objects) keys.add(object.key);
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
  const all = [...keys];
  for (let i = 0; i < all.length; i += 1000) await env.PHOTOS.delete(all.slice(i, i + 1000));
}

/**
 * DELETE /families/me: "すべて消す". Any member may call it.
 * Outside services go first (Gmail grant, Managed Agents sessions). If one of them fails, nothing in
 * D1 is deleted and the answer is 502 with what is pending, so calling again finishes the job; both
 * outside steps treat "already gone" as done. Then photos in R2, then every row of the family.
 */
export async function deleteEverything(request: Request, env: Env): Promise<Response> {
  const me = await requireMember(request, env);
  const familyId = me.familyId;
  const pending: string[] = [];

  const grant = await env.DB.prepare("SELECT refresh_token_enc FROM gmail_auth WHERE family_id = ?")
    .bind(familyId)
    .first<{ refresh_token_enc: string }>();
  if (grant && !(await revokeGmailGrant(env, grant.refresh_token_enc))) pending.push("gmail");

  const sessions = await env.DB.prepare(
    "SELECT DISTINCT agent_session_id AS id FROM cases WHERE family_id = ? AND agent_session_id IS NOT NULL",
  )
    .bind(familyId)
    .all<{ id: string }>();
  const deleted = await Promise.all(sessions.results.map((s) => deleteAgentSession(env, s.id)));
  if (deleted.includes(false)) pending.push("agent_sessions");

  if (pending.length > 0) return errorResponse(502, "cleanup_failed", { pending });

  await deleteFamilyPhotos(env, familyId);
  await env.DB.batch([
    env.DB.prepare("DELETE FROM relays WHERE case_id IN (SELECT id FROM cases WHERE family_id = ?)").bind(familyId),
    ...["cases", "alerts", "smiles", "invites", "gmail_auth", "members"].map((table) =>
      env.DB.prepare(`DELETE FROM ${table} WHERE family_id = ?`).bind(familyId),
    ),
    env.DB.prepare("DELETE FROM families WHERE id = ?").bind(familyId),
  ]);
  return noContent();
}
