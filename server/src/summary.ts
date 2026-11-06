// What the family's notice and card carry ("家族への知らせと解決" in docs/design.md): the one line,
// the reasons, and the AI's answer.
//
// Her words and the received text are never cut out and passed on as they are. The line is made
// from fixed labels, the reasons of the judgment, the domain, or a topic Claude wrote, and any line
// Claude wrote that repeats a stretch of what she said or what arrived is not used. The author
// decided this on 2026-11-04 (docs/dev-log.md).

/** This many characters in a row, the same as in her words or the received text, count as cut out. */
export const QUOTE_RUN = 8;

/** NFKC and lowercase, without spaces, punctuation, or symbols, so a comma put in between changes nothing. */
function squeeze(text: string): string {
  return text
    .normalize("NFKC")
    .toLowerCase()
    .replace(/[\s\p{P}\p{S}]+/gu, "");
}

/** True when `line` repeats QUOTE_RUN or more characters in a row from one of `sources`. */
export function repeats(line: string, sources: readonly string[]): boolean {
  const chars = [...squeeze(line)];
  if (chars.length < QUOTE_RUN) return false;
  const squeezed = sources.map(squeeze).filter((s) => [...s].length >= QUOTE_RUN);
  for (let i = 0; i + QUOTE_RUN <= chars.length; i++) {
    const window = chars.slice(i, i + QUOTE_RUN).join("");
    if (squeezed.some((s) => s.includes(window))) return true;
  }
  return false;
}

/** `repeats`, or puts something in quotation brackets: a line for the family that quotes. */
export function quotes(line: string, sources: readonly string[]): boolean {
  return /[「」『』"“”]/.test(line) || repeats(line, sources);
}

/**
 * The lines that may go to the family: the `fixed` ones (the rules' own wording) as they are, the
 * others only when they do not quote `sources`. When none is left, `fallback`.
 */
export function ownLines(
  lines: readonly string[],
  fixed: readonly string[],
  sources: readonly string[],
  fallback: readonly string[],
): string[] {
  const kept = lines.filter((l) => l.trim() !== "" && (fixed.includes(l) || !quotes(l, sources)));
  return kept.length > 0 ? kept : [...fallback];
}

// A number to call or a place to open, in a line for the mother (#53, review 4 of PR #41). A reason
// Claude wrote can carry the scam's callback number or a fake address, and her notice would show it
// as the app's own words. Eight digits or more in a row, once spaces, hyphens of any width, the long
// vowel mark, brackets, and dots between them are taken out, are a phone number: the Japanese ones
// have ten or eleven. Dates ("2026年11月6日") and amounts ("100,000円") stay under it. Short codes
// such as 110 or #9110 are left alone on purpose; they are public numbers, not the scam's.
// Middle dots, waves, slashes, and underscores between the digits count as gaps too (review 1 of PR #166).
const PHONE_GAPS = /[\s\-‐‑‒–—―−ー－()（）.・〜~/_]/g;
const PHONE = /\+81|\d{8,}/;
// A scheme, www., or a bare domain ("bank-check.example"), which also catches a mail address. The
// last label must be letters, so "1.2.3" is not one.
const ADDRESS = /https?:\/\/|www\.|[a-z0-9-]+(?:\.[a-z0-9-]+)*\.[a-z]{2,}/;

/** True when the line has something that looks like a phone number or a web or mail address. */
export function carriesContact(line: string): boolean {
  const text = line.normalize("NFKC").toLowerCase();
  // A dot written as 。 or [.], or with spaces round it, and hxxp for http still make an address.
  const dotted = text.replace(/\s*(?:。|\[\.\]|\.)\s*/g, ".").replace(/hxxp/g, "http");
  return PHONE.test(text.replace(PHONE_GAPS, "")) || ADDRESS.test(dotted);
}
