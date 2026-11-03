// "残す期間は30日" (docs/design.md): alerts, cases with their relays and agent sessions, and smiles
// with their photos are deleted 30 days after they were made. Families and members stay.

import { deleteAgentSession } from "./agents";

export const RETENTION_MS = 30 * 24 * 3600_000;

export async function purgeExpired(env: Env, now: number): Promise<void> {
  const cutoff = now - RETENTION_MS;

  // Agent sessions first: a case whose session could not be deleted stays until the next run.
  const oldCases = await env.DB.prepare(
    "SELECT id, agent_session_id FROM cases WHERE notified_at < ?",
  )
    .bind(cutoff)
    .all<{ id: string; agent_session_id: string | null }>();
  const keepCaseIds: string[] = [];
  for (const row of oldCases.results) {
    if (row.agent_session_id && !(await deleteAgentSession(env, row.agent_session_id))) {
      keepCaseIds.push(row.id);
    }
  }
  const deletable = oldCases.results.map((r) => r.id).filter((id) => !keepCaseIds.includes(id));

  const oldPhotos = await env.DB.prepare("SELECT r2_key FROM smiles WHERE created_at < ?")
    .bind(cutoff)
    .all<{ r2_key: string }>();
  const keys = oldPhotos.results.map((r) => r.r2_key);
  for (let i = 0; i < keys.length; i += 1000) await env.PHOTOS.delete(keys.slice(i, i + 1000));

  const statements = [
    env.DB.prepare("DELETE FROM alerts WHERE created_at < ?").bind(cutoff),
    env.DB.prepare("DELETE FROM smiles WHERE created_at < ?").bind(cutoff),
    env.DB.prepare("DELETE FROM invites WHERE expires_at < ?").bind(cutoff),
  ];
  for (const id of deletable) {
    statements.push(env.DB.prepare("DELETE FROM relays WHERE case_id = ?").bind(id));
    statements.push(env.DB.prepare("DELETE FROM cases WHERE id = ?").bind(id));
  }
  await env.DB.batch(statements);
}
