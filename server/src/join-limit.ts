// Tries at POST /invites/{code}/join per client address, counted in D1 (#67).
// The Rate Limiting binding JOIN_LIMITER stays in front as a cheap first filter, but Cloudflare's
// documentation says its counts are per location and approximate, and in production 23 tries in a
// row all got through. This counter holds "接続元ごとに60秒に5回まで" (docs/plan.md) by itself, so six
// digits cannot be walked through at the binding's pace.

import { keyedDigest } from "./secretbox";

export const JOIN_ATTEMPTS_PER_WINDOW = 5;
export const JOIN_WINDOW_MS = 60_000;
/** Rows older than this are deleted by the daily cleanup (src/retention.ts). */
export const JOIN_ATTEMPT_ROW_MS = 24 * 3600_000;
/**
 * Tries that may write to D1 in one UTC day, across all addresses. An address already in the table can
 * still write five rows a minute, so without this a few addresses could spend the Free plan's 100,000
 * row writes a day and stop the alerts, consultations, and smiles until midnight UTC. Each allowed try
 * writes about three rows (this day's count, the attempt row, its index), so joins stay near 6,000.
 * Past the cap every join answers 429 until the next UTC day; joins happen a few times per family.
 */
export const JOIN_WRITES_PER_DAY = 2000;

const JOIN_KEY_INFO = new TextEncoder().encode("mimamori join_attempts address");

/**
 * The address the count belongs to. IPv4 stays whole, and so does an IPv4 address written as IPv6
 * (::ffff:a.b.c.d or ::ffff:XXXX:XXXX). Other IPv6 is cut to its /48: a home line in Japan is usually
 * given a /48 or a /56 and can pick any address inside it, while family members live apart and so do
 * not share one. Anything that does not parse stays as it is.
 */
export function addressGroup(address: string): string {
  const ip = address.trim().toLowerCase().split("%")[0] ?? "";
  if (!ip.includes(":")) return ip;
  const hextets = expandIpv6(ip);
  if (!hextets) return ip;
  if (hextets.slice(0, 5).every((h) => h === 0) && hextets[5] === 0xffff) {
    const [hi = 0, lo = 0] = hextets.slice(6);
    return [hi >> 8, hi & 0xff, lo >> 8, lo & 0xff].join(".");
  }
  return `${hextets.slice(0, 3).map((h) => h.toString(16)).join(":")}::/48`;
}

/** The eight 16-bit groups of an IPv6 address, or null when it does not parse. */
function expandIpv6(ip: string): number[] | null {
  let text = ip;
  const dotted = /(\d+)\.(\d+)\.(\d+)\.(\d+)$/.exec(text);
  if (dotted) {
    const b = dotted.slice(1).map(Number);
    if (b.some((n) => n > 255)) return null;
    const [b0 = 0, b1 = 0, b2 = 0, b3 = 0] = b;
    text = `${text.slice(0, dotted.index)}${((b0 << 8) | b1).toString(16)}:${((b2 << 8) | b3).toString(16)}`;
  }
  const halves = text.split("::");
  if (halves.length > 2) return null;
  const left = halves[0] ? halves[0].split(":") : [];
  const right = halves.length === 2 && halves[1] ? halves[1].split(":") : [];
  const fill = 8 - left.length - right.length;
  if (halves.length === 2 ? fill < 0 : fill !== 0) return null;
  const parts = [...left, ...Array<string>(Math.max(0, fill)).fill("0"), ...right];
  if (!parts.every((h) => /^[0-9a-f]{1,4}$/.test(h))) return null;
  return parts.map((h) => parseInt(h, 16));
}

/** The UTC date, since D1's daily limits reset at midnight UTC. */
export function utcDay(now: number): string {
  return new Date(now).toISOString().slice(0, 10);
}

/**
 * Takes one try for this address and says whether it is allowed. Every try counts, the right code
 * too, as the contract says. A refused try writes nothing, so a flood from one address costs at most
 * five D1 writes a minute, and all addresses together at most JOIN_WRITES_PER_DAY tries a day. Each
 * count goes up in one statement, so simultaneous tries cannot all read the same count.
 */
export async function takeJoinAttempt(
  env: Env,
  address: string,
  now: number,
  writesPerDay: number = JOIN_WRITES_PER_DAY,
): Promise<boolean> {
  const key = await keyedDigest(env.TOKEN_ENC_KEY, JOIN_KEY_INFO, addressGroup(address), "join key unkeyed");
  const windowFrom = now - JOIN_WINDOW_MS;

  const current = await env.DB.prepare("SELECT window_start, count FROM join_attempts WHERE key = ?")
    .bind(key)
    .first<{ window_start: number; count: number }>();
  if (current && current.window_start > windowFrom && current.count >= JOIN_ATTEMPTS_PER_WINDOW) return false;

  // The day's count goes up only while it is under the cap; at the cap the WHERE leaves it alone, no
  // row comes back, and the try is refused without writing anything.
  const day = await env.DB.prepare(
    `INSERT INTO join_daily (day, writes) VALUES (?1, 1)
     ON CONFLICT (day) DO UPDATE SET writes = writes + 1 WHERE writes < ?2
     RETURNING writes`,
  )
    .bind(utcDay(now), writesPerDay)
    .first<{ writes: number }>();
  if (!day) return false;

  const row = await env.DB.prepare(
    `INSERT INTO join_attempts (key, window_start, count) VALUES (?1, ?2, 1)
     ON CONFLICT (key) DO UPDATE SET
       count = CASE WHEN window_start <= ?3 THEN 1 ELSE count + 1 END,
       window_start = CASE WHEN window_start <= ?3 THEN ?2 ELSE window_start END
     RETURNING count`,
  )
    .bind(key, now, windowFrom)
    .first<{ count: number }>();
  return (row?.count ?? Number.POSITIVE_INFINITY) <= JOIN_ATTEMPTS_PER_WINDOW;
}
