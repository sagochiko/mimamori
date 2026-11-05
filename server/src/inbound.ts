// What the routes that read received messages (SMS, Gmail) share: finding the first link, and deciding
// whether a message is worth Claude's look. The text is data to inspect, never instructions.

import { CODE_ONLY_REASON, FOREIGN_SENDER_REASON, type RuleResult } from "./rules";

/** The first https or http link in the text, for the one-an-hour grouping and the card's domain. */
export function firstLink(text: string): string | undefined {
  const match = /https?:\/\/[^\s"'<>「」『』（）()、。]+/i.exec(text);
  if (!match) return undefined;
  try {
    return new URL(match[0]).toString();
  } catch {
    return undefined;
  }
}

/**
 * Whether Claude should look. A level from the rules, or a sign too weak for a level, means unsure. A
 * message with no sign at all, one whose only sign is the overseas number (genuine services abroad send
 * bookings and codes), or one the rules read as only a verification code, is not queued: when Claude
 * fails, the queue treats an undecided message as level 2 and tells the family, which a genuine code,
 * delivery notice, or newsletter must not cause.
 */
export function worthAsking(rule: RuleResult): boolean {
  if (rule.level !== null) return true;
  if (rule.reasons.includes(CODE_ONLY_REASON)) return false;
  return rule.reasons.some((r) => r !== FOREIGN_SENDER_REASON);
}
