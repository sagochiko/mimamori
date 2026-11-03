// Cases and hand-off ("引き継ぎ" in docs/design.md, task 10 in docs/plan.md).
//
// D1 is the source of truth. A case moves only forward: notified -> accepted -> resolved. Every
// transition is one conditional UPDATE, so when two family members press "引き受ける" at once,
// exactly one statement finds the case still 'notified' and the other is told who has it.
//
// The flag that stops the AI's guidance is the state itself: once a case is no longer 'notified',
// a family member has taken over and the AI does not guide the protected person in that case any more
// (aiGuidanceStopped, deliverAiReply). That way the protected person never has two voices to choose from.

import { requireMember, type Role } from "./auth";
import { ExternalBudget } from "./budget";
import { HttpError, json, readJson } from "./http";
import { sendPush } from "./push";

export const UNANSWERED_AFTER_MS = 30 * 60_000;
/** Shown to the protected person when nobody accepted within 30 minutes. */
export const NO_REPLY_YET = "家族から返事がまだ。急ぐなら電話して";
export const RELAY_MAX = 200;
const AI_REPLY_MAX = 500;
const LIST_LIMIT = 50;
const WATCH_BATCH = 20;
/** A member who left has no row any more; their name is shown as this. */
const UNKNOWN_NAME = "家族";

export type CaseState = "notified" | "accepted" | "resolved";

export interface CaseView {
  id: string;
  alertId: string | null;
  state: CaseState;
  assigneeMemberId: string | null;
  assignee: { memberId: string; displayName: string } | null;
  notifiedAt: string;
  acceptedAt: string | null;
  resolvedAt: string | null;
  /** Set when the 30-minute watch told the protected person "家族から返事がまだ". */
  renotifiedAt: string | null;
  alert: { level: 1 | 2 | 3; source: string; summary: string; reasons: string[] } | null;
  /** What the AI told the protected person before a family member took over. */
  aiReply: string | null;
  relays: Array<{ id: string; fromMemberId: string; fromName: string; body: string; createdAt: string }>;
}

interface CaseRow {
  id: string;
  alert_id: string | null;
  state: CaseState;
  assignee_member_id: string | null;
  assignee_name: string | null;
  notified_at: number;
  accepted_at: number | null;
  resolved_at: number | null;
  renotified_at: number | null;
  ai_reply: string | null;
  level: 1 | 2 | 3 | null;
  source: string | null;
  summary: string | null;
  reasons: string | null;
}

interface MemberRow {
  id: string;
  family_id: string;
  role: Role;
  display_name: string;
}

function iso(ms: number | null): string | null {
  return ms === null ? null : new Date(ms).toISOString();
}

function nameOf(displayName: string | null | undefined): string {
  return displayName && displayName.trim() !== "" ? displayName : UNKNOWN_NAME;
}

function parseReasons(text: string | null): string[] {
  try {
    const value: unknown = JSON.parse(text ?? "[]");
    return Array.isArray(value) ? value.filter((r): r is string => typeof r === "string") : [];
  } catch {
    return [];
  }
}

/** The family's cases, newest first, optionally narrowed to one case or one alert. */
async function loadViews(
  env: Env,
  familyId: string,
  filter: { caseId?: string; alertId?: string } = {},
): Promise<CaseView[]> {
  const where = ["c.family_id = ?"];
  const binds: unknown[] = [familyId];
  if (filter.caseId !== undefined) {
    where.push("c.id = ?");
    binds.push(filter.caseId);
  }
  if (filter.alertId !== undefined) {
    where.push("c.alert_id = ?");
    binds.push(filter.alertId);
  }
  const rows = await env.DB.prepare(
    `SELECT c.id, c.alert_id, c.state, c.assignee_member_id, m.display_name AS assignee_name,
            c.notified_at, c.accepted_at, c.resolved_at, c.renotified_at, c.ai_reply,
            a.level, a.source, a.summary, a.reasons
       FROM cases c
       LEFT JOIN alerts a ON a.id = c.alert_id
       LEFT JOIN members m ON m.id = c.assignee_member_id
      WHERE ${where.join(" AND ")}
      ORDER BY c.notified_at DESC
      LIMIT ${LIST_LIMIT}`,
  )
    .bind(...binds)
    .all<CaseRow>();
  if (rows.results.length === 0) return [];

  const relays = await env.DB.prepare(
    `SELECT r.id, r.case_id, r.from_member_id, r.body, r.created_at, m.display_name
       FROM relays r LEFT JOIN members m ON m.id = r.from_member_id
      WHERE r.case_id IN (SELECT value FROM json_each(?))
      ORDER BY r.created_at`,
  )
    .bind(JSON.stringify(rows.results.map((r) => r.id)))
    .all<{ id: string; case_id: string; from_member_id: string; body: string; created_at: number; display_name: string | null }>();
  const relaysByCase = new Map<string, CaseView["relays"]>();
  for (const r of relays.results) {
    const list = relaysByCase.get(r.case_id) ?? [];
    list.push({
      id: r.id,
      fromMemberId: r.from_member_id,
      fromName: nameOf(r.display_name),
      body: r.body,
      createdAt: new Date(r.created_at).toISOString(),
    });
    relaysByCase.set(r.case_id, list);
  }

  return rows.results.map((r) => ({
    id: r.id,
    alertId: r.alert_id,
    state: r.state,
    assigneeMemberId: r.assignee_member_id,
    assignee:
      r.assignee_member_id === null ? null : { memberId: r.assignee_member_id, displayName: nameOf(r.assignee_name) },
    notifiedAt: new Date(r.notified_at).toISOString(),
    acceptedAt: iso(r.accepted_at),
    resolvedAt: iso(r.resolved_at),
    renotifiedAt: iso(r.renotified_at),
    alert:
      r.level === null
        ? null
        : { level: r.level, source: r.source ?? "", summary: r.summary ?? "", reasons: parseReasons(r.reasons) },
    aiReply: r.ai_reply,
    relays: relaysByCase.get(r.id) ?? [],
  }));
}

async function loadMember(env: Env, memberId: string): Promise<MemberRow> {
  const row = await env.DB.prepare("SELECT id, family_id, role, display_name FROM members WHERE id = ?")
    .bind(memberId)
    .first<MemberRow>();
  if (!row) throw new HttpError(403, "not_a_member");
  return row;
}

async function membersOf(env: Env, familyId: string): Promise<Array<{ id: string; role: Role; reachable: number }>> {
  const rows = await env.DB.prepare(
    "SELECT id, role, apns_token IS NOT NULL AS reachable FROM members WHERE family_id = ?",
  )
    .bind(familyId)
    .all<{ id: string; role: Role; reachable: number }>();
  return rows.results;
}

/** A failed notification must not undo the state change; the 30-minute watch is the safety net. */
async function notify(
  env: Env,
  memberIds: string[],
  payload: Parameters<typeof sendPush>[2],
  budget: ExternalBudget,
): Promise<void> {
  try {
    await sendPush(env, memberIds, payload, budget);
  } catch (error) {
    console.error("case notification failed", error instanceof Error ? error.name : typeof error);
  }
}

/**
 * Opens the case for an alert and tells every family member (not the protected person, whose screen
 * shows "家族に伝えました"). One case per alert: a second call, such as a retried queue message,
 * returns the same case without notifying again. Returns null when the alert does not exist.
 */
export async function openCase(
  env: Env,
  alertId: string,
  budget: ExternalBudget = new ExternalBudget(),
): Promise<CaseView | null> {
  const alert = await env.DB.prepare("SELECT id, family_id, level, summary FROM alerts WHERE id = ?")
    .bind(alertId)
    .first<{ id: string; family_id: string; level: number; summary: string }>();
  if (!alert) return null;

  const caseId = crypto.randomUUID();
  const inserted = await env.DB.prepare(
    `INSERT INTO cases (id, family_id, alert_id, state, notified_at)
     SELECT ?, ?, ?, 'notified', ? WHERE NOT EXISTS (SELECT 1 FROM cases WHERE alert_id = ?)`,
  )
    .bind(caseId, alert.family_id, alertId, Date.now(), alertId)
    .run();

  if (inserted.meta.changes === 1) {
    const family = (await membersOf(env, alert.family_id)).filter((m) => m.role === "family").map((m) => m.id);
    await notify(
      env,
      family,
      {
        title: `${alert.level}段階`,
        body: alert.summary.trim() === "" ? "相談が届きました" : alert.summary,
        data: { caseId },
        threadId: `case-${caseId}`,
      },
      budget,
    );
  }
  const [view] = await loadViews(env, alert.family_id, { alertId });
  return view ?? null;
}

/**
 * "引き受ける". Only a family member, and only the first one: the update applies only while the case
 * is 'notified'. Accepting again by the assignee returns the case; anyone else gets 409 with the
 * assignee's name. The protected person is told who is looking into it.
 */
export async function acceptCase(
  env: Env,
  caseId: string,
  memberId: string,
  budget: ExternalBudget = new ExternalBudget(),
): Promise<CaseView> {
  const me = await loadMember(env, memberId);
  if (me.role !== "family") throw new HttpError(403, "family_only");

  const won = await env.DB.prepare(
    `UPDATE cases SET state = 'accepted', assignee_member_id = ?, accepted_at = ?
      WHERE id = ? AND family_id = ? AND state = 'notified' RETURNING id`,
  )
    .bind(me.id, Date.now(), caseId, me.family_id)
    .first<{ id: string }>();

  const [view] = await loadViews(env, me.family_id, { caseId });
  if (!view) throw new HttpError(404, "case_not_found");
  if (!won) {
    if (view.state === "accepted" && view.assigneeMemberId === me.id) return view;
    throw new HttpError(409, view.state === "resolved" ? "already_resolved" : "already_accepted", {
      assignee: view.assignee,
    });
  }

  const protectedIds = (await membersOf(env, me.family_id)).filter((m) => m.role === "protected").map((m) => m.id);
  await notify(
    env,
    protectedIds,
    { body: `${nameOf(me.display_name)}が見ています`, data: { caseId }, threadId: `case-${caseId}` },
    budget,
  );
  return view;
}

/**
 * "母に返事する". Only the assignee of an accepted case. The text is kept as written (trimmed) and
 * sent to the protected person, whose iPhone reads it aloud with the normal system voice.
 */
export async function relay(
  env: Env,
  caseId: string,
  memberId: string,
  body: string,
  budget: ExternalBudget = new ExternalBudget(),
): Promise<{ id: string; createdAt: string }> {
  const text = typeof body === "string" ? body.trim() : "";
  if (text === "" || text.length > RELAY_MAX) throw new HttpError(400, "relay_body_invalid");
  const me = await loadMember(env, memberId);

  const relayId = crypto.randomUUID();
  const now = Date.now();
  // The check and the insert are one statement, so a reply cannot slip in after the case was resolved.
  const inserted = await env.DB.prepare(
    `INSERT INTO relays (id, case_id, from_member_id, body, created_at)
     SELECT ?, ?, ?, ?, ? WHERE EXISTS (
       SELECT 1 FROM cases WHERE id = ? AND family_id = ? AND state = 'accepted' AND assignee_member_id = ?)`,
  )
    .bind(relayId, caseId, me.id, text, now, caseId, me.family_id, me.id)
    .run();

  if (inserted.meta.changes !== 1) {
    const [view] = await loadViews(env, me.family_id, { caseId });
    if (!view) throw new HttpError(404, "case_not_found");
    if (view.state !== "accepted") throw new HttpError(409, "case_not_accepted");
    throw new HttpError(403, "not_assignee", { assignee: view.assignee });
  }

  const protectedIds = (await membersOf(env, me.family_id)).filter((m) => m.role === "protected").map((m) => m.id);
  await notify(
    env,
    protectedIds,
    { title: `${nameOf(me.display_name)}から`, body: text, data: { caseId, relayId }, threadId: `case-${caseId}` },
    budget,
  );
  return { id: relayId, createdAt: new Date(now).toISOString() };
}

/** "解決". Only the assignee of an accepted case; resolving again is not an error. */
export async function resolveCase(env: Env, caseId: string, memberId: string): Promise<CaseView> {
  const me = await loadMember(env, memberId);
  const done = await env.DB.prepare(
    `UPDATE cases SET state = 'resolved', resolved_at = ?
      WHERE id = ? AND family_id = ? AND state = 'accepted' AND assignee_member_id = ? RETURNING id`,
  )
    .bind(Date.now(), caseId, me.family_id, me.id)
    .first<{ id: string }>();

  const [view] = await loadViews(env, me.family_id, { caseId });
  if (!view) throw new HttpError(404, "case_not_found");
  if (done) return view;
  if (view.state === "notified") throw new HttpError(409, "case_not_accepted");
  if (view.state === "resolved" && view.assigneeMemberId === me.id) return view;
  throw new HttpError(403, "not_assignee", { assignee: view.assignee });
}

/**
 * True once a family member has taken over the case (or the case is gone): the AI must not guide
 * the protected person in it any more.
 */
export async function aiGuidanceStopped(env: Env, caseId: string): Promise<boolean> {
  const row = await env.DB.prepare("SELECT state FROM cases WHERE id = ?").bind(caseId).first<{ state: CaseState }>();
  return row?.state !== "notified";
}

/**
 * The gate every AI answer in a case passes on its way to the protected person (task 12's consult).
 * The answer is recorded for the family's card only while the case is still 'notified', checked in
 * the same statement, so an answer that was still being written when a family member accepted is
 * dropped. The caller sends the answer only when `delivered` is true, and otherwise tells the
 * protected person who is looking into it.
 */
export async function deliverAiReply(
  env: Env,
  caseId: string,
  text: string,
): Promise<{ delivered: true } | { delivered: false; assigneeName: string | null }> {
  const updated = await env.DB.prepare("UPDATE cases SET ai_reply = ? WHERE id = ? AND state = 'notified'")
    .bind(text.slice(0, AI_REPLY_MAX), caseId)
    .run();
  if (updated.meta.changes === 1) return { delivered: true };
  const row = await env.DB.prepare(
    "SELECT m.display_name FROM cases c LEFT JOIN members m ON m.id = c.assignee_member_id WHERE c.id = ?",
  )
    .bind(caseId)
    .first<{ display_name: string | null }>();
  return { delivered: false, assigneeName: row?.display_name ? nameOf(row.display_name) : null };
}

/**
 * Every 5 minutes (src/cron.ts). A case nobody accepted within 30 minutes: the protected person is
 * told "家族から返事がまだ。急ぐなら電話して" and every family member is notified again, once.
 * The state stays 'notified', so nothing tells the protected person it is solved or being handled.
 * A case whose whole family the budget cannot cover is left for a later tick, unclaimed.
 */
export async function watchUnanswered(env: Env, now: number, budget: ExternalBudget): Promise<void> {
  const due = await env.DB.prepare(
    `SELECT c.id, c.family_id, a.summary FROM cases c LEFT JOIN alerts a ON a.id = c.alert_id
      WHERE c.state = 'notified' AND c.renotified_at IS NULL AND c.notified_at <= ?
      ORDER BY c.notified_at LIMIT ${WATCH_BATCH}`,
  )
    .bind(now - UNANSWERED_AFTER_MS)
    .all<{ id: string; family_id: string; summary: string | null }>();

  for (const row of due.results) {
    const members = await membersOf(env, row.family_id);
    const needed = members.filter((m) => m.reachable).length;
    if (budget.remaining < needed) break;

    const claimed = await env.DB.prepare(
      "UPDATE cases SET renotified_at = ? WHERE id = ? AND state = 'notified' AND renotified_at IS NULL",
    )
      .bind(now, row.id)
      .run();
    if (claimed.meta.changes !== 1) continue;

    const threadId = `case-${row.id}`;
    await notify(
      env,
      members.filter((m) => m.role === "protected").map((m) => m.id),
      { body: NO_REPLY_YET, data: { caseId: row.id }, threadId },
      budget,
    );
    await notify(
      env,
      members.filter((m) => m.role === "family").map((m) => m.id),
      {
        title: "まだ誰も引き受けていません",
        body: row.summary && row.summary.trim() !== "" ? row.summary : "相談が届きました",
        data: { caseId: row.id },
        threadId,
      },
      budget,
    );
  }
}

// MARK: Routes

/** GET /cases: the caller's family's recent cases, newest first. */
export async function listCases(request: Request, env: Env): Promise<Response> {
  const me = await requireMember(request, env);
  return json({ cases: await loadViews(env, me.familyId) });
}

/** POST /cases/{id}/accept */
export async function acceptRoute(request: Request, env: Env, caseId: string): Promise<Response> {
  const me = await requireMember(request, env);
  return json(await acceptCase(env, caseId, me.id));
}

/** POST /cases/{id}/relay with { body } */
export async function relayRoute(request: Request, env: Env, caseId: string): Promise<Response> {
  const me = await requireMember(request, env);
  const { body } = await readJson(request);
  if (typeof body !== "string") throw new HttpError(400, "relay_body_invalid");
  return json(await relay(env, caseId, me.id, body), 201);
}

/** POST /cases/{id}/resolve */
export async function resolveRoute(request: Request, env: Env, caseId: string): Promise<Response> {
  const me = await requireMember(request, env);
  return json(await resolveCase(env, caseId, me.id));
}
