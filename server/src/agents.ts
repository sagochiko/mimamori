// Claude Managed Agents. Task 11 adds the research and hand-off sessions; this file starts with
// what "delete everything" needs: deleting a family's sessions, whose transcripts otherwise persist.

// https://platform.claude.com/docs/en/managed-agents/session-operations (Deleting a session),
// checked 2026-11-03: DELETE /v1/sessions/{id} with the managed-agents beta header.
const API = "https://api.anthropic.com/v1";
export const MANAGED_AGENTS_BETA = "managed-agents-2026-04-01";

export function agentHeaders(env: Env): Record<string, string> {
  return {
    "x-api-key": env.ANTHROPIC_API_KEY,
    "anthropic-version": "2023-06-01",
    "anthropic-beta": MANAGED_AGENTS_BETA,
  };
}

/**
 * Deletes one session with its events and sandbox. Returns true when the session is gone,
 * including when it was already deleted (404). A running session cannot be deleted; that comes back
 * as false, as does a request that throws, and the caller keeps its records so the deletion can be
 * retried.
 */
export async function deleteAgentSession(env: Env, sessionId: string): Promise<boolean> {
  try {
    const res = await fetch(`${API}/sessions/${encodeURIComponent(sessionId)}`, {
      method: "DELETE",
      headers: agentHeaders(env),
    });
    return res.ok || res.status === 404;
  } catch {
    // Network failure: same as "not deleted yet".
    return false;
  }
}
