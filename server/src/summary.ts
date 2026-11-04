// The one line the family's notice and card carry ("家族への知らせと解決" in docs/design.md).
//
// Her words and the received text are never cut out and passed on as they are. The line is made
// from fixed labels, the reasons of the judgment, the domain, or a topic Claude wrote, and any of
// those that repeats a stretch of what she said or what arrived is not used. The author decided this
// on 2026-11-04 (docs/dev-log.md).

/** This many characters in a row, the same as in her words or the received text, count as cut out. */
export const QUOTE_RUN = 8;

function squeeze(text: string): string {
  return text.normalize("NFKC").replace(/\s+/g, "").toLowerCase();
}

/**
 * True when `line` repeats QUOTE_RUN or more characters in a row from one of `sources`, compared after
 * NFKC, lowercasing, and dropping spaces, or puts something in quotation brackets.
 */
export function quotes(line: string, sources: readonly string[]): boolean {
  if (/[「」『』"“”]/.test(line)) return true;
  const chars = [...squeeze(line)];
  if (chars.length < QUOTE_RUN) return false;
  const squeezed = sources.map(squeeze).filter((s) => s.length >= QUOTE_RUN);
  for (let i = 0; i + QUOTE_RUN <= chars.length; i++) {
    const window = chars.slice(i, i + QUOTE_RUN).join("");
    if (squeezed.some((s) => s.includes(window))) return true;
  }
  return false;
}

/** The first line that is not empty and does not quote `sources`. */
export function firstOwnLine(lines: readonly string[], sources: readonly string[]): string | undefined {
  return lines.map((l) => l.trim()).find((l) => l !== "" && !quotes(l, sources));
}
