// "残す期間は30日" (docs/design.md): alerts, cases with their relays and agent sessions, and smiles
// with their photos are deleted 30 days after they were made. Families and members stay.

import { deleteAgentSession } from "./agents";
import type { ExternalBudget } from "./budget";

export const RETENTION_MS = 30 * 24 * 3600_000;

/**
 * Once a day. Only D1 and R2, so nothing outside can stop it. Cases that still have an agent
 * session are left to purgeExpiredSessions, which deletes the session first.
 */
export async function purgeExpired(env: Env, now: number): Promise<void> {
  const cutoff = now - RETENTION_MS;

  const oldPhotos = await env.DB.prepare("SELECT r2_key FROM smiles WHERE created_at < ?")
    .bind(cutoff)
    .all<{ r2_key: string }>();
  const keys = oldPhotos.results.map((r) => r.r2_key);
  for (let i = 0; i < keys.length; i += 1000) await env.PHOTOS.delete(keys.slice(i, i + 1000));

  await env.DB.batch([
    env.DB.prepare("DELETE FROM alerts WHERE created_at < ?").bind(cutoff),
    env.DB.prepare("DELETE FROM smiles WHERE created_at < ?").bind(cutoff),
    env.DB.prepare("DELETE FROM invites WHERE expires_at < ?").bind(cutoff),
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
  if (budget.remaining <= 0) return;
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
