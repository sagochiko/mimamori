// What the routes that read received messages (SMS, Gmail) share: finding the first link, and deciding
// whether a message or a mail is worth Claude's look. The text is data to inspect, never instructions.

import { CODE_ONLY_REASON, type RuleResult } from "./rules";

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
 * Whether Claude should look. Everything but what the rules read as only a verification code, with
 * or without a sign: since #137 the queue stays quiet when Claude gives nothing for a message the
 * rules found no sign in (decideFor in src/claude.ts), so a genuine delivery notice or newsletter can
 * go to Claude without becoming a false alarm, and a scam with no sign the rules know ("携帯が壊れて
 * 番号が変わった") is not missed. Codes are left out to keep Claude's calls down: they come often, and
 * the rules read them on their own. The rules give the code reason for SMS only, so a code in a mail
 * is still asked about. The SMS and mail routes share this gate, and eval/lib/score.ts uses it too,
 * so the numbers are measured on the same path. Pages have their own, narrower gate
 * (src/page-gate.ts), since she opens many more pages than she receives messages.
 */
export function worthAsking(rule: RuleResult): boolean {
  return !(rule.level === null && rule.reasons.includes(CODE_ONLY_REASON));
}
