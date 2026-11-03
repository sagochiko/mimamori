// Family token and device key ("家族の印と端末の鍵" in docs/plan.md).
// A deviceKey is shown to the device once and stored only as a SHA-256 hash. It carries 256 bits
// of randomness, so a plain hash is enough; there is nothing to brute-force.

import { HttpError } from "./http";

export type Role = "protected" | "family";

export interface Member {
  id: string;
  familyId: string;
  role: Role;
  displayName: string;
}

export function base64url(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function randomBytes(n: number): Uint8Array {
  return crypto.getRandomValues(new Uint8Array(n));
}

/** 32 random bytes, base64url (43 characters). */
export function newDeviceKey(): string {
  return base64url(randomBytes(32));
}

/**
 * 16 random bytes as 32 lowercase hex digits. It sits in the /sms/ and /dns-query/ paths, and
 * Cloudflare's log redaction hides runs of 32 or more hex digits, so the token never shows in logs.
 */
export function newFamilyToken(): string {
  return [...randomBytes(16)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** Six decimal digits, uniform (rejection sampling avoids modulo bias). */
export function newInviteCode(): string {
  const limit = Math.floor(0x1_0000_0000 / 1_000_000) * 1_000_000;
  for (;;) {
    const [n] = crypto.getRandomValues(new Uint32Array(1));
    if (n !== undefined && n < limit) return String(n % 1_000_000).padStart(6, "0");
  }
}

export async function hashDeviceKey(deviceKey: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(deviceKey));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function bearer(request: Request): string | null {
  const header = request.headers.get("Authorization");
  if (!header) return null;
  const match = /^Bearer\s+(\S+)$/i.exec(header);
  return match?.[1] ?? null;
}

/**
 * The member behind `Authorization: Bearer <deviceKey>`, or a 401.
 * A member who left the family has no row, so their key stops working on the next call.
 */
export async function requireMember(request: Request, env: Env): Promise<Member> {
  const key = bearer(request);
  if (!key) throw new HttpError(401, "device_key_required");
  const row = await env.DB.prepare(
    "SELECT id, family_id, role, display_name FROM members WHERE device_key_hash = ?",
  )
    .bind(await hashDeviceKey(key))
    .first<{ id: string; family_id: string; role: Role; display_name: string }>();
  if (!row) throw new HttpError(401, "device_key_invalid");
  return { id: row.id, familyId: row.family_id, role: row.role, displayName: row.display_name };
}
