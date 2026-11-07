// Claude calls and Managed Agents researches per family and JST day, counted in D1 (the public-release
// audit of 2026-11-07, point 1). ExternalBudget (src/budget.ts) only counts within one invocation, so
// before this a key for the mother's role could call Claude through /consult and /page without end.
// Past a cap the caller acts as when Claude gives no answer: the rules alone decide, and nothing new
// is said to her (docs/design.md, 失敗したとき).

import { jstDate } from "./time";

/**
 * Claude calls a family may make in one JST day: each consultation (one call, two with the web
 * search), and each SMS, mail, or page the judge queue asks about. A mother consults a few times a
 * day and receives some tens of messages; a judge trying the app, and the eval runs, stay well under a
 * hundred. At 200 a key used for abuse costs at most about 200 Sonnet calls with a search each a day,
 * around ten dollars (more with images), and the organisation's monthly limit in the Anthropic Console
 * caps the rest.
 */
export const CLAUDE_CALLS_PER_FAMILY_DAY = 200;
/**
 * Managed Agents researches a family may start in one JST day. One starts only after a level 1 or 2
 * notice, a handful a day for a real family, and each is capped at RESEARCH_BUDGET_CENTS (src/agents.ts),
 * so 20 a day bounds the abuse at about ten dollars a family a day.
 */
export const RESEARCH_STARTS_PER_FAMILY_DAY = 20;

type Column = "claude_calls" | "research_starts";

/**
 * Takes one from the family's count for the day and says whether it was under the cap. The count goes
 * up in one statement only while it is under the cap, so simultaneous callers cannot all pass at the
 * last one, and a refused take writes nothing. A D1 failure is no ticket, never a throw: the caller
 * then answers with the rules, and the mother never gets an error in place of an answer.
 */
async function take(env: Env, familyId: string, now: number, column: Column, cap: number): Promise<boolean> {
  try {
    // column is one of the two names above, never from a request.
    const row = await env.DB.prepare(
      `INSERT INTO claude_daily (family_id, day, claude_calls, research_starts)
       VALUES (?1, ?2, ${column === "claude_calls" ? 1 : 0}, ${column === "research_starts" ? 1 : 0})
       ON CONFLICT (family_id, day) DO UPDATE SET ${column} = ${column} + 1 WHERE ${column} < ?3
       RETURNING ${column} AS n`,
    )
      .bind(familyId, jstDate(now), cap)
      .first<{ n: number }>();
    return row !== null && row.n <= cap;
  } catch (error) {
    console.error("claude cap unread", error instanceof Error ? error.name : typeof error);
    return false;
  }
}

/** One Claude call for the family today; false past CLAUDE_CALLS_PER_FAMILY_DAY. */
export function takeClaudeCall(env: Env, familyId: string, now: number, cap = CLAUDE_CALLS_PER_FAMILY_DAY): Promise<boolean> {
  return take(env, familyId, now, "claude_calls", cap);
}

/** One research start for the family today; false past RESEARCH_STARTS_PER_FAMILY_DAY. */
export function takeResearchStart(
  env: Env,
  familyId: string,
  now: number,
  cap = RESEARCH_STARTS_PER_FAMILY_DAY,
): Promise<boolean> {
  return take(env, familyId, now, "research_starts", cap);
}
