// Cases ("家族への知らせと解決" in docs/design.md, task 10 in docs/plan.md).
//
// The family only needs to know three things about the protected person: what she is troubled by,
// whether it is dangerous, and whether it was solved. Every family member sees the same card, and
// whoever talked with her presses "解決". Nobody takes a case over, and the AI keeps answering her:
// accepting a case and writing her a reply were dropped on 2026-11-04 (docs/dev-log.md).
//
// D1 is the source of truth. A case moves only forward: notified -> resolved, in one conditional
// UPDATE, so when two family members press "解決" at once only one of them tells the others.
//
// Columns kept from the earlier hand-off and no longer read or written: accepted_at, and the relays
// table (still deleted with the case). assignee_member_id now holds who pressed "解決". A row left in
// the old 'accepted' state counts as not resolved.
//
// family_notified_at is the one record that a family device took the case's first notice, and it is
// written only after one did. Sending is claimed in family_notice_claimed_at, a column of its own, so
// a notice still being sent is never read as told: not by her answer to a consultation, her screen,
// or the 30-minute watch (#64).

import { storedEvidence, type Evidence } from "./agents";
import { requireMember, type Role } from "./auth";
import { summaryLine } from "./consult-summary";
import { D1_CALLS_PER_TICK, ExternalBudget } from "./budget";
import { HttpError, json } from "./http";
import { sendPush } from "./push";

export const UNANSWERED_AFTER_MS = 30 * 60_000;
/** Shown to the protected person when the case was not resolved within 30 minutes. */
export const NO_REPLY_YET = "家族から返事がまだ。急ぐなら電話して";
/**
 * Shown to the protected person in place of "家族に伝えました" while no family device took the case's
 * notice (family_notified_at is NULL), and by the 30-minute watch in place of NO_REPLY_YET, so she
 * does not think the family knows (#60).
 */
export const NOT_REACHED = "家族に届いていません。急ぐなら電話して";
/** The title of the family's second notice, 30 minutes after the first. */
export const NOT_RESOLVED_YET = "まだ解決していません";
/**
 * The title of the case's notice: a word for the level, as on the family's card (`Level.familyBadge`
 * in ios/Core). "1段階" told the family nothing; the author chose these on 2026-11-08. None reads as safe.
 */
export function familyBadge(level: number): string {
  return level === 1 ? "危ない" : level === 2 ? "確かめて" : "念のため";
}
const AI_REPLY_MAX = 500;
const LIST_LIMIT = 50;
const WATCH_BATCH = 20;
/** A member who left has no row any more; their name is shown as this. */
const UNKNOWN_NAME = "家族";

export type CaseState = "notified" | "resolved";

export interface CaseView {
  id: string;
  alertId: string | null;
  state: CaseState;
  notifiedAt: string;
  resolvedAt: string | null;
  /** Who pressed "解決" ("(名前)が解決"). Null while the case is open. */
  resolvedBy: { memberId: string; displayName: string } | null;
  /** Set when the 30-minute watch told the protected person "家族から返事がまだ". */
  renotifiedAt: string | null;
  /**
   * When a family device first took the case's notice, or null while none did. Her screen says
   * NOT_REACHED instead of "家族に伝えました" while it is null (#60).
   */
  familyNotifiedAt: string | null;
  /** The summary is one line made by the rules or Claude, never her words or the received text cut out. */
  alert: {
    level: 1 | 2 | 3;
    source: string;
    summary: string;
    reasons: string[];
    evidence: Evidence[];
    /** A consultation's summary from fixed choices (#271): the fixed line, or null when there is none. */
    digest: string | null;
  } | null;
  /** The last answer the AI gave the protected person in this case. */
  aiReply: string | null;
}

interface CaseRow {
  id: string;
  alert_id: string | null;
  state: string;
  assignee_member_id: string | null;
  resolver_name: string | null;
  notified_at: number;
  resolved_at: number | null;
  renotified_at: number | null;
  family_notified_at: number | null;
  ai_reply: string | null;
  level: 1 | 2 | 3 | null;
  source: string | null;
  summary: string | null;
  reasons: string | null;
  evidence: string | null;
  summary_topic: string | null;
  summary_step: string | null;
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
  // A card a family member removed (#280) is not listed, and so cannot be resolved again either.
  const where = ["c.family_id = ?", "c.hidden_at IS NULL"];
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
    `SELECT c.id, c.alert_id, c.state, c.assignee_member_id, m.display_name AS resolver_name,
            c.notified_at, c.resolved_at, c.renotified_at, c.family_notified_at, c.ai_reply,
            a.level, a.source, a.summary, a.reasons, a.evidence,
            a.summary_topic, a.summary_step
       FROM cases c
       LEFT JOIN alerts a ON a.id = c.alert_id
       LEFT JOIN members m ON m.id = c.assignee_member_id
      WHERE ${where.join(" AND ")}
      ORDER BY c.notified_at DESC
      LIMIT ${LIST_LIMIT}`,
  )
    .bind(...binds)
    .all<CaseRow>();

  return rows.results.map((r) => {
    const resolved = r.state === "resolved";
    return {
      id: r.id,
      alertId: r.alert_id,
      state: resolved ? "resolved" : "notified",
      notifiedAt: new Date(r.notified_at).toISOString(),
      resolvedAt: resolved ? iso(r.resolved_at) : null,
      resolvedBy:
        resolved && r.assignee_member_id !== null
          ? { memberId: r.assignee_member_id, displayName: nameOf(r.resolver_name) }
          : null,
      renotifiedAt: iso(r.renotified_at),
      familyNotifiedAt: iso(r.family_notified_at),
      alert:
        r.level === null
          ? null
          : {
              level: r.level,
              source: r.source ?? "",
              summary: r.summary ?? "",
              reasons: parseReasons(r.reasons),
              // What the research in the background found (task 11); [] until it is read, or when none.
              evidence: storedEvidence(r.evidence),
              digest: summaryLine(r.summary_topic, r.summary_step, r.level),
            },
      aiReply: r.ai_reply,
    };
  });
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
  if (memberIds.length === 0) return;
  try {
    await sendPush(env, memberIds, payload, budget);
  } catch (error) {
    console.error("case notification failed", error instanceof Error ? error.name : typeof error);
  }
}

/**
 * openCase could not tell the family yet. The case is kept, untold (family_notified_at is NULL): the
 * caller retries the same alert, and if it gives up, the 5-minute tick retries the first notice.
 */
export class CaseNoticeDeferred extends Error {
  override name = "CaseNoticeDeferred";
  constructor(readonly reason: "no_budget" | "not_delivered") {
    super(reason);
  }
}

/** A day after the case opened, a first notice is no longer worth retrying, nor a reminder worth sending. */
const FIRST_NOTICE_RETRY_MS = 24 * 3600_000;
/**
 * A claim on the first notice older than this is taken over by the next sender: the Worker that took
 * it stopped mid-send and will not let go of it. Five minutes is the tick's interval, so the next tick
 * or the one after it sends the notice; no send to APNs takes that long.
 */
export const CLAIM_TTL_MS = 5 * 60_000;
const WATCH_MAX_AGE_MS = FIRST_NOTICE_RETRY_MS;
const FIRST_NOTICE_BATCH = 20;
/**
 * The D1 calls one case can take in the tick (#178, src/budget.ts): the claim, the family's members,
 * their device tokens, and letting go of the claim.
 */
const FIRST_NOTICE_D1 = 4;
/**
 * The most of the tick's D1 calls the first-notice retry may use. A notice APNs keeps failing (not 410)
 * is not given up for a day, and without this nine of them would take every tick's calls and keep the
 * 30-minute watch from telling her NOT_REACHED (急ぐなら電話して). Half leaves the watch room for five.
 */
const FIRST_NOTICE_D1_SHARE = D1_CALLS_PER_TICK / 2;
/** The same for one reminder: the members, the claim, and the device tokens of each of the two notices. */
const WATCH_D1 = 4;

/**
 * The first notice of a case to every family member. family_notice_claimed_at is the claim: set
 * before sending so two callers never both send, and let go of once the notice went out or no family
 * device took it, so the next try sends it. family_notified_at is set only when a family device took
 * it, in the same statement that lets go of the claim. "already" means told, or another caller is
 * sending it right now; either way this call sends nothing, and the case reads as told only once
 * family_notified_at is set. A family with no device to send to is not told either (#60): the case
 * waits, and the 5-minute tick sends it once someone registers a device. A case the family resolved
 * before the notice got through is not claimed (#49): a family member already talked with her, and a
 * retry by the queue or the tick would tell the family again about something they settled. The old
 * 'accepted' state counts as not resolved, as everywhere else in this file.
 *
 * When this call's claim was taken over (it ran past CLAIM_TTL_MS) and its notice still went out,
 * family_notified_at stays NULL and the case keeps reading as not told until the newer claim's sender
 * gets through: she hears NOT_REACHED although the family was told, never the other way round.
 */
async function tellFamily(
  env: Env,
  c: { id: string; familyId: string; level: number | null; summary: string | null },
  budget: ExternalBudget,
): Promise<"told" | "already" | "no_budget" | "not_delivered"> {
  const claimedAt = Date.now();
  const claimed = await env.DB.prepare(
    `UPDATE cases SET family_notice_claimed_at = ?
      WHERE id = ? AND family_notified_at IS NULL AND state != 'resolved'
        AND (family_notice_claimed_at IS NULL OR family_notice_claimed_at < ?)`,
  )
    .bind(claimedAt, c.id, claimedAt - CLAIM_TTL_MS)
    .run();
  if (claimed.meta.changes !== 1) return "already";

  const sent = await sendCaseNotice(env, c, budget);
  // Each lets go of this call's own claim only: one taken over belongs to the newer sender.
  if (sent === "told") {
    await env.DB.prepare(
      "UPDATE cases SET family_notified_at = ?, family_notice_claimed_at = NULL WHERE id = ? AND family_notice_claimed_at = ?",
    )
      .bind(Date.now(), c.id, claimedAt)
      .run();
  } else {
    await env.DB.prepare(
      "UPDATE cases SET family_notice_claimed_at = NULL WHERE id = ? AND family_notice_claimed_at = ?",
    )
      .bind(c.id, claimedAt)
      .run();
  }
  return sent;
}

/** The case's notice to every family device: the level as a word and the one-line summary. Never throws. */
async function sendCaseNotice(
  env: Env,
  c: { id: string; familyId: string; level: number | null; summary: string | null },
  budget: ExternalBudget,
): Promise<"told" | "no_budget" | "not_delivered"> {
  const family = (await membersOf(env, c.familyId)).filter((m) => m.role === "family");
  const reachable = family.filter((m) => m.reachable).length;
  if (reachable === 0) return "not_delivered";
  if (!budget.takeMany(reachable)) return "no_budget";

  let told = false;
  try {
    const results = await sendPush(
      env,
      family.map((m) => m.id),
      {
        ...(c.level === null ? {} : { title: familyBadge(c.level) }),
        body: c.summary && c.summary.trim() !== "" ? c.summary : "相談が届きました",
        data: { caseId: c.id },
        threadId: `case-${c.id}`,
      },
      // The tickets were taken above; sendPush spends exactly those.
      new ExternalBudget(reachable),
    );
    told = results.some((r) => r.status === "sent");
  } catch (error) {
    console.error("case notification failed", error instanceof Error ? error.name : typeof error);
  }
  return told ? "told" : "not_delivered";
}

/**
 * Tells the family again about a case they were already told of, because its level just became
 * heavier (a later consultation in the same conversation), or a sign of a scam came to a level 2
 * case that had none (#114, src/consult.ts). When the budget or APNs fails, it is
 * logged and the case goes back to waiting for its first notice, so the 5-minute tick
 * (sendFirstNotices) sends it with the heavier level. Returns whether a family device took it.
 */
export async function tellFamilyHeavier(env: Env, caseId: string, budget: ExternalBudget): Promise<boolean> {
  const row = await env.DB.prepare(
    `SELECT c.id, c.family_id, a.level, a.summary FROM cases c JOIN alerts a ON a.id = c.alert_id
      WHERE c.id = ? AND c.family_notified_at IS NOT NULL`,
  )
    .bind(caseId)
    .first<{ id: string; family_id: string; level: number; summary: string | null }>();
  if (!row) return false;
  const sent = await sendCaseNotice(
    env,
    { id: row.id, familyId: row.family_id, level: row.level, summary: row.summary },
    budget,
  );
  if (sent === "told") return true;
  // Back on the first notice's retry: the 5-minute tick sends it again, with the heavier level. No
  // claim can be held while family_notified_at is set; it is cleared too, so none holds the retry back.
  console.error("case heavier notice deferred", sent);
  await env.DB.prepare("UPDATE cases SET family_notified_at = NULL, family_notice_claimed_at = NULL WHERE id = ?")
    .bind(caseId)
    .run();
  return false;
}

/**
 * Opens the case for an alert and tells every family member (not the protected person, whose screen
 * shows "家族に伝えました", or NOT_REACHED while no family device took it). One case per alert.
 * Returns null when the alert does not exist.
 *
 * The case row is kept from the start, so the protected person's screen, the family's list, and the
 * 30-minute watch see it whatever happens to the notice. When the shared budget cannot cover every
 * family device, or no family device took the notice (none registered counts too), the case stays
 * untold and CaseNoticeDeferred is thrown; calling again with the same alert tells the family, and a
 * call after they were told, or after the family resolved the case (#49), returns the case without
 * notifying or taking tickets. A call while another
 * caller is sending the notice does the same and does not throw; the case reads as untold until that
 * send gets through, and the tick retries it if it does not. When at least one family member was told,
 * the case counts as told and the watch covers the others.
 */
export async function openCase(env: Env, alertId: string, budget: ExternalBudget): Promise<CaseView | null> {
  const alert = await env.DB.prepare("SELECT id, family_id, level, summary FROM alerts WHERE id = ?")
    .bind(alertId)
    .first<{ id: string; family_id: string; level: number; summary: string }>();
  if (!alert) return null;

  await env.DB.prepare(
    `INSERT INTO cases (id, family_id, alert_id, state, notified_at)
     SELECT ?, ?, ?, 'notified', ? WHERE NOT EXISTS (SELECT 1 FROM cases WHERE alert_id = ?)`,
  )
    .bind(crypto.randomUUID(), alert.family_id, alertId, Date.now(), alertId)
    .run();
  const row = await env.DB.prepare("SELECT id, family_notified_at FROM cases WHERE alert_id = ?")
    .bind(alertId)
    .first<{ id: string; family_notified_at: number | null }>();

  if (row && row.family_notified_at === null) {
    const result = await tellFamily(
      env,
      { id: row.id, familyId: alert.family_id, level: alert.level, summary: alert.summary },
      budget,
    );
    if (result === "no_budget" || result === "not_delivered") throw new CaseNoticeDeferred(result);
  }
  const [view] = await loadViews(env, alert.family_id, { alertId });
  return view ?? null;
}

/**
 * Every 5 minutes, before the 30-minute watch (src/cron.ts): the first notice of a case nobody in the
 * family was told about yet, as when the queue stopped retrying while APNs kept failing. Newest
 * first, for a day after the case opened, within the tick's shared budget. Only families with a
 * device to notify: a family that registered none would fill the batch and keep another family's
 * failed notice from being retried. Its cases are picked up once someone registers a device. A case
 * whose notice another caller is sending right now is left to it, unless that claim is older than
 * CLAIM_TTL_MS (tellFamily). The tick's D1 calls stop it the same way as its budget: the cases that do
 * not fit are not claimed, and the next tick sends them.
 */
export async function sendFirstNotices(env: Env, now: number, budget: ExternalBudget): Promise<void> {
  if (budget.d1Remaining < 1 + FIRST_NOTICE_D1) return;
  // Outside the tick d1Remaining is unlimited, and so is this.
  const leave = budget.d1Remaining - FIRST_NOTICE_D1_SHARE;
  const due = await env.DB.prepare(
    `SELECT c.id, c.family_id, a.level, a.summary FROM cases c LEFT JOIN alerts a ON a.id = c.alert_id
      WHERE c.state != 'resolved' AND c.family_notified_at IS NULL AND c.notified_at > ?
        AND EXISTS (SELECT 1 FROM members m
                     WHERE m.family_id = c.family_id AND m.role = 'family' AND m.apns_token IS NOT NULL)
      ORDER BY c.notified_at DESC LIMIT ${FIRST_NOTICE_BATCH}`,
  )
    .bind(now - FIRST_NOTICE_RETRY_MS)
    .all<{ id: string; family_id: string; level: number | null; summary: string | null }>();
  for (const c of due.results) {
    // Left for the next tick before it is claimed, so it is not held for CLAIM_TTL_MS.
    if (budget.d1Remaining < FIRST_NOTICE_D1 || budget.d1Remaining - FIRST_NOTICE_D1 < leave) break;
    const result = await tellFamily(
      env,
      { id: c.id, familyId: c.family_id, level: c.level, summary: c.summary },
      budget,
    );
    if (result === "no_budget") break;
  }
}

/**
 * "解決". Any family member, once: the update applies only while the case is not resolved, so of two
 * members pressing it at once, one records it and tells the rest of the family "(名前)が解決". Pressing
 * it again, by anyone, returns the case without telling anyone again. The protected person is not
 * notified; her card for the case goes away.
 */
export async function resolveCase(
  env: Env,
  caseId: string,
  memberId: string,
  budget: ExternalBudget = new ExternalBudget(),
): Promise<CaseView> {
  const me = await loadMember(env, memberId);
  if (me.role !== "family") throw new HttpError(403, "family_only");

  const done = await env.DB.prepare(
    `UPDATE cases SET state = 'resolved', resolved_at = ?, assignee_member_id = ?
      WHERE id = ? AND family_id = ? AND state != 'resolved' RETURNING id`,
  )
    .bind(Date.now(), me.id, caseId, me.family_id)
    .first<{ id: string }>();

  const [view] = await loadViews(env, me.family_id, { caseId });
  if (!view) throw new HttpError(404, "case_not_found");
  if (!done) return view;

  const others = (await membersOf(env, me.family_id)).filter((m) => m.role === "family" && m.id !== me.id);
  await notify(
    env,
    others.map((m) => m.id),
    { body: `${nameOf(me.display_name)}が解決`, data: { caseId }, threadId: `case-${caseId}` },
    budget,
  );
  return view;
}

/**
 * Removes a resolved card from the family's list (#280), for every family device. Any family member;
 * the protected person's screen has no resolved cases. The row stays with hidden_at set, so a judge
 * message still retried for the alert does not open the case again (openCase's NOT EXISTS sees it, as
 * #49 does for a resolved case); the AI's answer and the old relays go now, and the 30-day cleanup
 * deletes the row. Another family's case, a missing one, and one already removed are 404; a case not
 * resolved (the old 'accepted' state too) is 409. Nobody is notified.
 */
export async function hideCase(env: Env, caseId: string, memberId: string): Promise<void> {
  const me = await loadMember(env, memberId);
  if (me.role !== "family") throw new HttpError(403, "family_only");

  const [hidden] = await env.DB.batch<{ id: string }>([
    env.DB.prepare(
      `UPDATE cases SET hidden_at = ?, ai_reply = NULL
        WHERE id = ? AND family_id = ? AND state = 'resolved' AND hidden_at IS NULL RETURNING id`,
    ).bind(Date.now(), caseId, me.family_id),
    // Only once the case above is hidden: a refused removal leaves everything as it was.
    env.DB.prepare(
      `DELETE FROM relays WHERE case_id IN
         (SELECT id FROM cases WHERE id = ? AND family_id = ? AND hidden_at IS NOT NULL)`,
    ).bind(caseId, me.family_id),
  ]);
  if (hidden && hidden.results.length === 1) return;

  const row = await env.DB.prepare("SELECT state, hidden_at FROM cases WHERE id = ? AND family_id = ?")
    .bind(caseId, me.family_id)
    .first<{ state: string; hidden_at: number | null }>();
  if (!row || row.hidden_at !== null) throw new HttpError(404, "case_not_found");
  throw new HttpError(409, "case_not_resolved");
}

/** Keeps the AI's latest answer to the protected person for the family's card. The AI always answers her. */
export async function recordAiReply(env: Env, caseId: string, text: string): Promise<void> {
  await env.DB.prepare("UPDATE cases SET ai_reply = ? WHERE id = ?").bind(text.slice(0, AI_REPLY_MAX), caseId).run();
}

/**
 * Every 5 minutes (src/cron.ts). A case not resolved within 30 minutes: the protected person is told
 * "家族から返事がまだ。急ぐなら電話して" (NOT_REACHED instead while the family was never told) and
 * every family member is notified again, once. The state
 * stays as it is, so nothing tells the protected person it is solved. A case whose whole family the
 * budget cannot cover, or that the tick's D1 calls would not fit, is left for a later tick, unclaimed. A case more than a day old is not
 * reminded about any more, so rows that never got a reminder do not all come back at once.
 */
export async function watchUnanswered(env: Env, now: number, budget: ExternalBudget): Promise<void> {
  if (budget.d1Remaining < 1 + WATCH_D1) return;
  const due = await env.DB.prepare(
    `SELECT c.id, c.family_id, c.family_notified_at, a.summary, a.source FROM cases c LEFT JOIN alerts a ON a.id = c.alert_id
      WHERE c.state != 'resolved' AND c.renotified_at IS NULL AND c.notified_at <= ? AND c.notified_at > ?
      ORDER BY c.notified_at LIMIT ${WATCH_BATCH}`,
  )
    .bind(now - UNANSWERED_AFTER_MS, now - WATCH_MAX_AGE_MS)
    .all<{
      id: string;
      family_id: string;
      family_notified_at: number | null;
      summary: string | null;
      source: string | null;
    }>();

  for (const row of due.results) {
    // Before the claim: a claimed reminder that was never sent would not be sent again.
    if (budget.d1Remaining < WATCH_D1) break;
    // Only her own consultation reminds her: one the app found is not on her strip (#239), so a
    // "急ぐなら電話して" about it would point at nothing she can see. The family is reminded of every case.
    const toMother = row.source === "consult";
    const members = (await membersOf(env, row.family_id)).filter((m) => toMother || m.role !== "protected");
    const needed = members.filter((m) => m.reachable).length;
    if (budget.remaining < needed) break;

    const claimed = await env.DB.prepare(
      "UPDATE cases SET renotified_at = ? WHERE id = ? AND state != 'resolved' AND renotified_at IS NULL",
    )
      .bind(now, row.id)
      .run();
    if (claimed.meta.changes !== 1) continue;

    const threadId = `case-${row.id}`;
    await notify(
      env,
      members.filter((m) => m.role === "protected").map((m) => m.id),
      { body: row.family_notified_at === null ? NOT_REACHED : NO_REPLY_YET, data: { caseId: row.id }, threadId },
      budget,
    );
    await notify(
      env,
      members.filter((m) => m.role === "family").map((m) => m.id),
      {
        title: NOT_RESOLVED_YET,
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

/** POST /cases/{id}/resolve */
export async function resolveRoute(request: Request, env: Env, caseId: string): Promise<Response> {
  const me = await requireMember(request, env);
  return json(await resolveCase(env, caseId, me.id));
}

/** DELETE /cases/{id}: removes a resolved card from the family's list (#280). */
export async function hideRoute(request: Request, env: Env, caseId: string): Promise<Response> {
  const me = await requireMember(request, env);
  await hideCase(env, caseId, me.id);
  return new Response(null, { status: 204 });
}
