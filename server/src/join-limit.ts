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

const JOIN_KEY_INFO = new TextEncoder().encode("mimamori join_attempts address");

/**
 * The address the count belongs to. IPv4 stays whole; IPv6 is cut to its /64, since one home or
 * phone line is given a whole /64 and can pick any address inside it. Anything else stays as it is.
 */
export function addressGroup(address: string): string {
  const ip = address.trim().toLowerCase().split("%")[0] ?? "";
  if (!ip.includes(":")) return ip;
  const mapped = /^::ffff:(\d+\.\d+\.\d+\.\d+)$/.exec(ip);
  if (mapped?.[1]) return mapped[1];
  const [head, tail] = ip.split("::", 2);
  const left = head ? head.split(":") : [];
  const right = tail ? tail.split(":") : [];
  const hextets = ip.includes("::")
    ? [...left, ...Array<string>(Math.max(0, 8 - left.length - right.length)).fill("0"), ...right]
    : left;
  const first = hextets.slice(0, 4).map((h) => (/^[0-9a-f]{1,4}$/.test(h) ? parseInt(h, 16).toString(16) : h));
  return `${first.join(":")}::/64`;
}

/**
 * Takes one try for this address and says whether it is allowed. Every try counts, the right code
 * too, as the contract says. A refused try writes nothing, so a flood from one address costs at most
 * five D1 writes a minute; the count goes up in one statement, so simultaneous tries cannot all read
 * the same count.
 */
export async function takeJoinAttempt(env: Env, address: string, now: number): Promise<boolean> {
  const key = await keyedDigest(env.TOKEN_ENC_KEY, JOIN_KEY_INFO, addressGroup(address), "join key unkeyed");
  const windowFrom = now - JOIN_WINDOW_MS;

  const current = await env.DB.prepare("SELECT window_start, count FROM join_attempts WHERE key = ?")
    .bind(key)
    .first<{ window_start: number; count: number }>();
  if (current && current.window_start > windowFrom && current.count >= JOIN_ATTEMPTS_PER_WINDOW) return false;

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
