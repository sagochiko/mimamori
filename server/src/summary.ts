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
