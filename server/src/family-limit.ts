// Tries at POST /families per client address, counted in D1 like the joins (src/join-limit.ts). Making
// a family needs no key, and with an invite and a join it gives a key for the mother's role, which can
// call Claude (the public-release audit of 2026-11-07, point 1). The per-family daily caps
// (src/claude-limit.ts) bound each family; this bounds how many families one address can make.

import { addressGroup } from "./join-limit";
import { keyedDigest } from "./secretbox";

/**
 * Families one address may make in an hour. A judge or a family member makes one, and makes it again
 * only after "すべて消す" or a reinstall; the trial mode makes none (it plays fixed answers). Five an
 * hour leaves room for a household behind one address and for trying again, and keeps one address to
 * 120 families a day.
 */
export const FAMILY_CREATES_PER_WINDOW = 5;
export const FAMILY_CREATE_WINDOW_MS = 3600_000;

const FAMILY_KEY_INFO = new TextEncoder().encode("mimamori family_attempts address");

/**
 * Takes one try for this address and says whether it is allowed. A refused try writes nothing, and the
 * count goes up in one statement, so simultaneous tries cannot all read the same count.
 */
export async function takeFamilyCreate(env: Env, address: string, now: number): Promise<boolean> {
  const key = await keyedDigest(env.TOKEN_ENC_KEY, FAMILY_KEY_INFO, addressGroup(address), "family key unkeyed");
  const windowFrom = now - FAMILY_CREATE_WINDOW_MS;

  const current = await env.DB.prepare("SELECT window_start, count FROM family_attempts WHERE key = ?")
    .bind(key)
    .first<{ window_start: number; count: number }>();
  if (current && current.window_start > windowFrom && current.count >= FAMILY_CREATES_PER_WINDOW) return false;

  const row = await env.DB.prepare(
    `INSERT INTO family_attempts (key, window_start, count) VALUES (?1, ?2, 1)
     ON CONFLICT (key) DO UPDATE SET
       count = CASE WHEN window_start <= ?3 THEN 1 ELSE count + 1 END,
       window_start = CASE WHEN window_start <= ?3 THEN ?2 ELSE window_start END
     RETURNING count`,
  )
    .bind(key, now, windowFrom)
    .first<{ count: number }>();
  return (row?.count ?? Number.POSITIVE_INFINITY) <= FAMILY_CREATES_PER_WINDOW;
}
