// The Claude side of `--mode rules+claude`: the same requestClaudeJudgment and decide that the judge
// queue uses (server/src/claude.ts, task 6), so the numbers measure what the family would get.
// Consultations go the way POST /consult takes them instead (#74): the consultation Claude
// (requestClaudeConsult in server/src/consult-judge.ts), asked only when her words do not tell the
// fake-police script, and combined by judgeConsult there (eval/lib/score.ts).
// Without an API key the mode stops with a clear error instead of making up numbers.
// No Node APIs here, so the server's Vitest (in workerd) can import this file; eval/run.ts passes the
// key from the environment.

import { type ClaudeJudgment, decide, requestClaudeJudgment } from "../../server/src/claude";
import { type ClaudeConsult, requestClaudeConsult } from "../../server/src/consult-judge";
import type { RuleInput, RuleResult } from "../../server/src/rules/index";

/**
 * What Claude itself answered, before the rules' floor and the injection step, kept in
 * eval/out/dev-latest.json so a false alarm can be traced to Claude's level or to the code (#109).
 */
export interface ClaudeSeen {
  level: 1 | 2 | 3;
  reasons: string[];
  injection_suspected: boolean;
}

/** The level the family and the mother would get once Claude's judgment is combined with the rules. */
export interface CombinedJudgment {
  level: 1 | 2 | 3 | null;
  /** Claude gave nothing usable, so the rules stood alone (the mother would see "確かめ中"). */
  checking?: boolean;
  /** Claude's own answer; absent when it gave nothing usable. */
  claude?: ClaudeSeen;
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

/** The consultation Claude: her words and the rules on them in, its answer or null for any failure out. */
export type ConsultJudge = (text: string, rule: RuleResult) => Promise<ClaudeConsult | null>;

export const unavailableConsultJudge: ConsultJudge = async () => {
  throw new JudgeUnavailableError();
};

/** Lays Claude's answer over the rule result exactly as the judge queue does. */
export function claudeJudge(ask: AskClaude): Judge {
  return async (input, rule) => {
    const answer = await ask(input, rule);
    const decision = decide(rule, answer);
    const combined: CombinedJudgment = { level: decision.level, checking: decision.checking };
    if (answer !== null) {
      combined.claude = {
        level: answer.level,
        reasons: answer.reasons,
        injection_suspected: answer.injection_suspected,
      };
    }
    return combined;
  };
}

/** The judge for rules+claude runs, or one that stops the run when there is no key. */
export function loadJudge(apiKey: string | undefined): Judge {
  if (!apiKey) return unavailableJudge;
  return claudeJudge((input, rule) => requestClaudeJudgment({ ANTHROPIC_API_KEY: apiKey }, input, rule));
}

/** The consultation Claude for rules+claude runs (no earlier turns), or one that stops the run without a key. */
export function loadConsultJudge(apiKey: string | undefined): ConsultJudge {
  if (!apiKey) return unavailableConsultJudge;
  return (text, rule) => requestClaudeConsult({ ANTHROPIC_API_KEY: apiKey }, text, rule);
}
