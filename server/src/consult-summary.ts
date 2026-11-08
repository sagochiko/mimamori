// The family's summary of a consultation (#271, task 11 in docs/plan.md). A Managed Agents session
// picks one topic and one next step from fixed choices through its own tool (report_summary); the
// family's card shows the fixed line for those choices, never anything the agent wrote. Free text was
// not taken for the same reason as the research's evidence (PR #183): every filter we tried let a
// reassuring paraphrase through. No choice reads as "safe" or "nothing to worry about", and the agent
// cannot change the level: at level 1 the next step is always CALL_NOW, whatever it chose.
//
// This file holds the choices and the reading of the tool's input only, so cases.ts and agents.ts can
// both use it without importing each other.

export const SUMMARY_TOOL = "report_summary";

/** The topic of the consultation, as the family reads it. Keys go to D1, labels only to GET /cases. */
export const SUMMARY_TOPICS = {
  police: "警察を名乗る連絡",
  money: "送金や振込",
  code: "認証コードや暗証番号",
  app: "アプリや設定",
  delivery: "宅配や料金の連絡",
  other: "そのほかの相談",
} as const satisfies Record<string, string>;

/**
 * What the family does next. There is no "next time you talk" choice: level 1 and 2 both tell her to
 * stop and wait for the family, so a step that could wait days would read as "it can wait".
 */
export const SUMMARY_STEPS = {
  call_now: "すぐ電話して確かめる",
  call_today: "今日のうちに電話する",
} as const satisfies Record<string, string>;

export type SummaryTopic = keyof typeof SUMMARY_TOPICS;
export type SummaryStep = keyof typeof SUMMARY_STEPS;

export interface ConsultSummary {
  topic: SummaryTopic;
  step: SummaryStep;
}

function isTopic(value: unknown): value is SummaryTopic {
  return typeof value === "string" && Object.hasOwn(SUMMARY_TOPICS, value);
}

function isStep(value: unknown): value is SummaryStep {
  return typeof value === "string" && Object.hasOwn(SUMMARY_STEPS, value);
}

/**
 * The report tool's input as two choices, or null for anything else: a missing or unknown key, a
 * label in place of a key, extra text. Null leaves the card as it is. `level` is the alert's level
 * when the result is read; at 1 the step is CALL_NOW whatever the agent chose.
 */
export function parseSummary(value: unknown, level: number): ConsultSummary | null {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return null;
  const { topic, next_step: step } = value as Record<string, unknown>;
  if (!isTopic(topic) || !isStep(step)) return null;
  return { topic, step: level === 1 ? "call_now" : step };
}

/**
 * The one line on the family's card for stored keys, or null when there is no summary or a key is
 * not one of ours. The level is the alert's level now: a case made heavier after the summary was read
 * still shows CALL_NOW at level 1.
 */
export function summaryLine(topic: string | null, step: string | null, level: number | null): string | null {
  if (!isTopic(topic) || !isStep(step)) return null;
  const next: SummaryStep = level === 1 ? "call_now" : step;
  return `${SUMMARY_TOPICS[topic]} / ${SUMMARY_STEPS[next]}`;
}
