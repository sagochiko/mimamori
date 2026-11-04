// The Claude side of `--mode rules+claude`: the same requestClaudeJudgment and decide that the judge
// queue uses (server/src/claude.ts, task 6), so the numbers measure what the family would get.
// Without an API key the mode stops with a clear error instead of making up numbers.
// No Node APIs here, so the server's Vitest (in workerd) can import this file; eval/run.ts passes the
// key from the environment.

import { type ClaudeJudgment, decide, requestClaudeJudgment } from "../../server/src/claude";
import type { RuleInput, RuleResult } from "../../server/src/rules/index";

/** The level the family and the mother would get once Claude's judgment is combined with the rules. */
export interface CombinedJudgment {
  level: 1 | 2 | 3 | null;
  /** Claude gave nothing usable, so the rules stood alone (the mother would see "確かめ中"). */
  checking?: boolean;
}

export type Judge = (input: RuleInput, rule: RuleResult) => Promise<CombinedJudgment>;

export type AskClaude = (input: RuleInput, rule: RuleResult) => Promise<ClaudeJudgment | null>;

export class JudgeUnavailableError extends Error {
  constructor() {
    super("--mode rules+claude needs ANTHROPIC_API_KEY in the environment; nothing was measured or recorded");
    this.name = "JudgeUnavailableError";
  }
}

export const unavailableJudge: Judge = async () => {
  throw new JudgeUnavailableError();
};

/** Lays Claude's answer over the rule result exactly as the judge queue does. */
export function claudeJudge(ask: AskClaude): Judge {
  return async (input, rule) => {
    const decision = decide(rule, await ask(input, rule));
    return { level: decision.level, checking: decision.checking };
  };
}

/** The judge for rules+claude runs, or one that stops the run when there is no key. */
export function loadJudge(apiKey: string | undefined): Judge {
  if (!apiKey) return unavailableJudge;
  return claudeJudge((input, rule) => requestClaudeJudgment({ ANTHROPIC_API_KEY: apiKey }, input, rule));
}
