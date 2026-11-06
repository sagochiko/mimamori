// "残す期間は30日" (docs/design.md): alerts, cases with their relays and agent sessions, and smiles
// with their photos are deleted 30 days after they were made. Families and members stay. Join tries
// (src/join-limit.ts) are kept only a day.

import { deleteAgentSession } from "./agents";
import type { ExternalBudget } from "./budget";
import { JOIN_ATTEMPT_ROW_MS } from "./join-limit";

export const RETENTION_MS = 30 * 24 * 3600_000;

/**
 * Once a day. Only D1 and R2, so nothing outside can stop it, and it does not look at the tick's D1
 * calls either: its two are part of the room left below the limit (src/budget.ts). Cases that still have an agent
 * session are left to purgeExpiredSessions, which deletes the session first.
 */
export async function purgeExpired(env: Env, now: number): Promise<void> {
  const cutoff = now - RETENTION_MS;

  const oldPhotos = await env.DB.prepare("SELECT r2_key FROM smiles WHERE created_at < ? AND r2_key != ''")
    .bind(cutoff)
    .all<{ r2_key: string }>();
  // A reply without a photo has r2_key '' and nothing in R2 (migrations/0005); its row goes below.
  const keys = oldPhotos.results.map((r) => r.r2_key);
  for (let i = 0; i < keys.length; i += 1000) await env.PHOTOS.delete(keys.slice(i, i + 1000));

  await env.DB.batch([
    // An alert whose research session is still there waits for purgeExpiredSessions (task 11).
    env.DB.prepare("DELETE FROM alerts WHERE created_at < ? AND investigation_session_id IS NULL").bind(cutoff),
    env.DB.prepare("DELETE FROM smiles WHERE created_at < ?").bind(cutoff),
    env.DB.prepare("DELETE FROM invites WHERE expires_at < ?").bind(cutoff),
    env.DB.prepare("DELETE FROM join_attempts WHERE window_start < ?").bind(now - JOIN_ATTEMPT_ROW_MS),
    env.DB.prepare(
      "DELETE FROM relays WHERE case_id IN (SELECT id FROM cases WHERE notified_at < ? AND agent_session_id IS NULL)",
    ).bind(cutoff),
    env.DB.prepare("DELETE FROM cases WHERE notified_at < ? AND agent_session_id IS NULL").bind(cutoff),
  ]);
}

/**
 * Every tick. Deletes the agent sessions of old cases, as many as the budget allows, then those
 * cases. A session that cannot be deleted yet keeps its case for a later tick; the random order
 * keeps a few stuck sessions from blocking the rest.
 */
export async function purgeExpiredSessions(env: Env, now: number, budget: ExternalBudget): Promise<void> {
  // Each half is a lookup and one write (#178, src/budget.ts).
  if (budget.remaining <= 0 || budget.d1Remaining < 2) return;
  await purgeCaseSessions(env, now, budget);
  await purgeExpiredResearch(env, now, budget);
}

async function purgeCaseSessions(env: Env, now: number, budget: ExternalBudget): Promise<void> {
  const due = await env.DB.prepare(
    "SELECT id, agent_session_id FROM cases WHERE notified_at < ? AND agent_session_id IS NOT NULL ORDER BY random() LIMIT ?",
  )
    .bind(now - RETENTION_MS, budget.remaining)
    .all<{ id: string; agent_session_id: string }>();
  if (due.results.length === 0) return;

  const outcomes = await Promise.all(
    due.results.map(async (row) =>
      budget.take() && (await deleteAgentSession(env, row.agent_session_id)) ? row.id : null,
    ),
  );
  const done = JSON.stringify(outcomes.filter((id): id is string => id !== null));
  await env.DB.batch([
    env.DB.prepare("DELETE FROM relays WHERE case_id IN (SELECT value FROM json_each(?))").bind(done),
    env.DB.prepare("DELETE FROM cases WHERE id IN (SELECT value FROM json_each(?))").bind(done),
  ]);
}

/** The research sessions of old alerts (task 11), then those alerts, with what the budget has left. */
async function purgeExpiredResearch(env: Env, now: number, budget: ExternalBudget): Promise<void> {
  if (budget.remaining <= 0 || budget.d1Remaining < 2) return;
  const due = await env.DB.prepare(
    "SELECT id, investigation_session_id AS session FROM alerts WHERE created_at < ? AND investigation_session_id IS NOT NULL ORDER BY random() LIMIT ?",
  )
    .bind(now - RETENTION_MS, budget.remaining)
    .all<{ id: string; session: string }>();
  if (due.results.length === 0) return;
  const outcomes = await Promise.all(
    due.results.map(async (row) => (budget.take() && (await deleteAgentSession(env, row.session)) ? row.id : null)),
  );
  const done = JSON.stringify(outcomes.filter((id): id is string => id !== null));
  await env.DB.prepare("DELETE FROM alerts WHERE id IN (SELECT value FROM json_each(?))").bind(done).run();
}
