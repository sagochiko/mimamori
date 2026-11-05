// JST, the one time zone the family's clocks are read in (the daily jobs, the smile deadline).

export const JST_OFFSET_MS = 9 * 3600_000;

/** The JST calendar date of a moment, as YYYY-MM-DD. */
export function jstDate(ms: number): string {
  return new Date(ms + JST_OFFSET_MS).toISOString().slice(0, 10);
}

/** Epoch ms of 00:00 JST on the JST day of `ms`. */
export function jstMidnight(ms: number): number {
  const day = 24 * 3600_000;
  return Math.floor((ms + JST_OFFSET_MS) / day) * day - JST_OFFSET_MS;
}
