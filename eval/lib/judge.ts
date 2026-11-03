// The Claude side of `--mode rules+claude`. Task 6 (#7) builds the real judge in server/src/judge.ts
// and plugs it in here; until then the mode stops with a clear error instead of making up numbers.
// No Node APIs here, so the server's Vitest (in workerd) can import this file.

import type { RuleInput, RuleResult } from "../../server/src/rules/index";

/** The level the family and the mother would get once Claude's judgment is combined with the rules. */
export interface CombinedJudgment {
  level: 1 | 2 | 3 | null;
}

export type Judge = (input: RuleInput, rule: RuleResult) => Promise<CombinedJudgment>;

export class JudgeUnavailableError extends Error {
  constructor() {
    super("judge not available until #7: --mode rules+claude needs the Claude judge from task 6");
    this.name = "JudgeUnavailableError";
  }
}

export const unavailableJudge: Judge = async () => {
  throw new JudgeUnavailableError();
};

/** The judge for rules+claude runs. #7 replaces this with the real one. */
export function loadJudge(): Judge {
  return unavailableJudge;
}
