// Task 17 "見守りの自己点検" (docs/design.md, "アプリからの声かけ"; #19). When she turns notifications
// off or the app stops running in the background, every other check goes quiet without a word. So her
// iPhone says it is still watching (POST /heartbeat), and the family hears when it stops.
//
// The body carries only whether notifications and background refresh are on. The time kept is the
// server's own, so a wrong clock on the iPhone cannot hide a gap. Free disk space is never sent: Apple
// does not let it, or anything judged from it, leave the device (reason 85F4.1 in
// ios/App/PrivacyInfo.xcprivacy).
//
// Every notice is a fixed sentence with her display name, never words from Claude or from a message.
// They are quiet (no sound, "passive"): none is an incident to act on at once, and the 48-hour notice
// is sent by the tick at any hour, the middle of the night included.

import { requireMember, type Member } from "./auth";
import { ExternalBudget } from "./budget";
import { HttpError, noContent, readJson } from "./http";
import { sendPush, type PushPayload } from "./push";

export const HEARTBEAT_LAPSE_MS = 48 * 3600_000;
/** Members looked at per tick; the rest wait for the next tick, oldest gap first. */
const LAPSES_PER_TICK = 20;
/** D1 calls of one member's notice in the tick (#178): the claim, the family, their tokens, giving the claim back. */
const LAPSE_D1 = 4;

export const LAPSE_TEXT = (name: string) => `${name}の見守りが止まっています`;
const NOTIFICATIONS_OFF_TEXT = (name: string) => `${name}のiPhoneで、みまもりの通知が切られています`;
// 「アプリのバックグラウンド更新」 is the switch in Settings > 一般 (BACKGROUND_APP_REFRESH in the ja strings of
// the iOS 26.5 and 27.1 simulator runtimes, read on 2026-11-07).
const BACKGROUND_OFF_TEXT = (name: string) => `${name}のiPhoneで、みまもりの「アプリのバックグラウンド更新」が切られています`;

const THREAD = "watch";

export interface HeartbeatBody {
  notifications: boolean;
  backgroundRefresh: boolean;
}

/** Exactly the two booleans; anything else in the body is dropped, never stored. */
function parseBody(value: Record<string, unknown>): HeartbeatBody {
  const { notifications, backgroundRefresh } = value;
  if (typeof notifications !== "boolean" || typeof backgroundRefresh !== "boolean") {
    throw new HttpError(400, "heartbeat_invalid");
  }
  return { notifications, backgroundRefresh };
}

/** `POST /heartbeat`. Only the protected member's iPhone is watched. */
export async function heartbeatRoute(request: Request, env: Env): Promise<Response> {
  const me = await requireMember(request, env);
  if (me.role !== "protected") throw new HttpError(403, "protected_only");
  const body = parseBody(await readJson(request));
  await recordHeartbeat(env, me, body, Date.now(), new ExternalBudget());
  return noContent();
}

async function familyOf(env: Env, familyId: string): Promise<string[]> {
  const rows = await env.DB.prepare("SELECT id FROM members WHERE family_id = ? AND role = 'family'")
    .bind(familyId)
    .all<{ id: string }>();
  return rows.results.map((r) => r.id);
}

/** True when the notice reached APNs or was skipped for good; false when it waits for more budget. */
async function tellFamily(env: Env, familyId: string, body: string, budget: ExternalBudget): Promise<boolean> {
  const payload: PushPayload = { body, quiet: true, threadId: THREAD };
  const results = await sendPush(env, await familyOf(env, familyId), payload, budget);
  return !results.some((r) => r.status === "skipped" && r.reason === "no_budget");
}

type Flag = "notifications_off" | "background_refresh_off";

/**
 * One setting the device reported. Off: claim the flag (only one of two racing heartbeats wins), tell
 * the family, and give the claim back if the budget ran out so the next heartbeat tells them. On: clear
 * it, so turning it off again is told again.
 */
async function reportSetting(
  env: Env,
  me: Member,
  flag: Flag,
  isOn: boolean,
  text: string,
  budget: ExternalBudget,
): Promise<void> {
  if (isOn) {
    await env.DB.prepare(`UPDATE members SET ${flag} = 0 WHERE id = ?`).bind(me.id).run();
    return;
  }
  const claim = await env.DB.prepare(
    `UPDATE members SET ${flag} = 1 WHERE id = ? AND (${flag} IS NULL OR ${flag} = 0)`,
  )
    .bind(me.id)
    .run();
  if (claim.meta.changes !== 1) return;
  const giveBack = () =>
    env.DB.prepare(`UPDATE members SET ${flag} = NULL WHERE id = ? AND ${flag} = 1`).bind(me.id).run();
  let told: boolean;
  try {
    told = await tellFamily(env, me.familyId, text, budget);
  } catch (error) {
    // D1 failed after the claim: without this the flag would stay 1 and the family never hear.
    await giveBack();
    throw error;
  }
  if (!told) await giveBack();
}

/** Keeps the server's time, ends the current gap, and tells the family about a setting turned off. */
export async function recordHeartbeat(
  env: Env,
  me: Member,
  body: HeartbeatBody,
  now: number,
  budget: ExternalBudget,
): Promise<void> {
  await env.DB.prepare("UPDATE members SET heartbeat_at = ?, heartbeat_lapse_notified_at = NULL WHERE id = ?")
    .bind(now, me.id)
    .run();
  await reportSetting(env, me, "notifications_off", body.notifications, NOTIFICATIONS_OFF_TEXT(me.displayName), budget);
  await reportSetting(
    env,
    me,
    "background_refresh_off",
    body.backgroundRefresh,
    BACKGROUND_OFF_TEXT(me.displayName),
    budget,
  );
}

/**
 * The 5-minute tick: a protected member whose last heartbeat is 48 hours old or more, and whose family
 * was not told about this gap yet, is told once. A member that never sent one is left alone, so builds
 * from before the heartbeat do not set it off.
 */
export async function watchHeartbeats(env: Env, now: number, budget: ExternalBudget): Promise<void> {
  if (budget.d1Remaining < 1 + LAPSE_D1) return;
  const due = await env.DB.prepare(
    `SELECT id, family_id, display_name FROM members
      WHERE role = 'protected' AND heartbeat_at IS NOT NULL AND heartbeat_at <= ?
        AND heartbeat_lapse_notified_at IS NULL
      ORDER BY heartbeat_at LIMIT ?`,
  )
    .bind(now - HEARTBEAT_LAPSE_MS, LAPSES_PER_TICK)
    .all<{ id: string; family_id: string; display_name: string }>();

  for (const member of due.results) {
    if (budget.d1Remaining < LAPSE_D1) break;
    const claim = await env.DB.prepare(
      `UPDATE members SET heartbeat_lapse_notified_at = ?
        WHERE id = ? AND heartbeat_lapse_notified_at IS NULL AND heartbeat_at <= ?`,
    )
      .bind(now, member.id, now - HEARTBEAT_LAPSE_MS)
      .run();
    if (claim.meta.changes !== 1) continue;
    const giveBack = () =>
      env.DB.prepare(
        "UPDATE members SET heartbeat_lapse_notified_at = NULL WHERE id = ? AND heartbeat_lapse_notified_at = ?",
      )
        .bind(member.id, now)
        .run();
    let told: boolean;
    try {
      told = await tellFamily(env, member.family_id, LAPSE_TEXT(member.display_name), budget);
    } catch (error) {
      await giveBack();
      throw error;
    }
    if (!told) {
      // The push budget is spent: the rest wait for the next tick.
      await giveBack();
      break;
    }
  }
}
