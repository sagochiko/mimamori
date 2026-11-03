// APNs. Token-based auth: a JWT signed with ES256 over the .p8 key
// (developer.apple.com, "Establishing a token-based connection to APNs", checked 2026-11-03).
// APNs rejects a token older than one hour and refuses refreshes more often than every 20 minutes
// (TooManyProviderTokenUpdates), so one token is kept for 50 minutes per isolate and rebuilt after
// that. When APNs rejects a token early, it is rebuilt no sooner than 20 minutes after the last build.
//
// Workers' fetch does not speak HTTP/2 itself; in production Cloudflare upgrades the connection.
// Local `wrangler dev` may fail here, so the real send is checked from a deployed Worker.

import { base64url } from "./auth";

export interface PushPayload {
  title?: string;
  body: string;
  /** Extra keys next to "aps", read by the app (for example the case id). */
  data?: Record<string, string | number | boolean>;
  /** Groups notifications of one case together on the lock screen. */
  threadId?: string;
}

export type PushResult =
  | { memberId: string; status: "sent"; httpStatus: number }
  | { memberId: string; status: "skipped"; reason: "no_device_token" | "unknown_member" }
  | { memberId: string; status: "failed"; httpStatus?: number; reason: string };

export const JWT_REUSE_MS = 50 * 60_000;
export const JWT_MIN_REBUILD_MS = 20 * 60_000;

const HOSTS = {
  sandbox: "https://api.sandbox.push.apple.com",
  production: "https://api.push.apple.com",
} as const;

interface CachedJwt {
  identity: string;
  issuedAtMs: number;
  // A promise, so concurrent sends share one token instead of each signing their own
  // (several new tokens at once would trip APNs' refresh limit).
  jwt: Promise<string>;
  /** APNs said ExpiredProviderToken or InvalidProviderToken for this token. */
  rejected: boolean;
}
let cached: CachedJwt | null = null;

/** Tests start each case from an empty cache. */
export function resetApnsJwtCache(): void {
  cached = null;
}

function pemToDer(pem: string): Uint8Array {
  const b64 = pem
    .replace(/\\n/g, "\n")
    .replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
}

function encodeJson(value: unknown): string {
  return base64url(new TextEncoder().encode(JSON.stringify(value)));
}

async function signJwt(env: Env, iat: number): Promise<string> {
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(env.APNS_KEY_P8),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const signingInput = `${encodeJson({ alg: "ES256", kid: env.APNS_KEY_ID })}.${encodeJson({ iss: env.APNS_TEAM_ID, iat })}`;
  // WebCrypto returns the raw r||s form that JWS expects for ES256.
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64url(new Uint8Array(signature))}`;
}

function keyIdentity(env: Env): string {
  // Kept only in memory; a new key, key id, or team starts a new token at once.
  return `${env.APNS_TEAM_ID}:${env.APNS_KEY_ID}:${env.APNS_KEY_P8}`;
}

function apnsJwt(env: Env, nowMs: number): Promise<string> {
  const identity = keyIdentity(env);
  if (cached && cached.identity === identity) {
    const age = nowMs - cached.issuedAtMs;
    if (age < JWT_MIN_REBUILD_MS || (!cached.rejected && age < JWT_REUSE_MS)) return cached.jwt;
  }
  const iat = Math.floor(nowMs / 1000);
  const entry: CachedJwt = { identity, issuedAtMs: iat * 1000, jwt: signJwt(env, iat), rejected: false };
  entry.jwt.catch(() => {
    if (cached === entry) cached = null;
  });
  cached = entry;
  return entry.jwt;
}

function apsBody(payload: PushPayload): Record<string, unknown> {
  const aps: Record<string, unknown> = {
    alert: payload.title === undefined ? { body: payload.body } : { title: payload.title, body: payload.body },
    sound: "default",
  };
  if (payload.threadId) aps["thread-id"] = payload.threadId;
  return { ...payload.data, aps };
}

interface Target {
  id: string;
  apns_token: string | null;
  apns_env: "sandbox" | "production" | null;
}

async function sendOne(env: Env, target: Target & { apns_token: string }, payload: PushPayload): Promise<PushResult> {
  const host = HOSTS[target.apns_env ?? "production"];
  const jwt = apnsJwt(env, Date.now());
  const res = await fetch(`${host}/3/device/${target.apns_token}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${await jwt}`,
      "apns-topic": env.APNS_TOPIC,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body: JSON.stringify(apsBody(payload)),
  });
  if (res.ok) return { memberId: target.id, status: "sent", httpStatus: res.status };

  const reason = ((await res.json().catch(() => ({}))) as { reason?: string }).reason ?? "unknown";
  if (res.status === 410 || reason === "BadDeviceToken" || reason === "Unregistered") {
    // The app was removed or the token changed; the app registers a new one on its next launch.
    await env.DB.prepare("UPDATE members SET apns_token = NULL WHERE id = ? AND apns_token = ?")
      .bind(target.id, target.apns_token)
      .run();
  }
  if ((reason === "ExpiredProviderToken" || reason === "InvalidProviderToken") && cached?.jwt === jwt) {
    cached.rejected = true;
  }
  return { memberId: target.id, status: "failed", httpStatus: res.status, reason };
}

/**
 * Sends one alert to each member. Members without a device token are skipped, not failed.
 * Results come back in the order of memberIds. A 200 from APNs means accepted, not seen.
 */
export async function sendPush(env: Env, memberIds: string[], payload: PushPayload): Promise<PushResult[]> {
  if (memberIds.length === 0) return [];
  const placeholders = memberIds.map(() => "?").join(", ");
  const rows = await env.DB.prepare(
    `SELECT id, apns_token, apns_env FROM members WHERE id IN (${placeholders})`,
  )
    .bind(...memberIds)
    .all<Target>();
  const byId = new Map(rows.results.map((r) => [r.id, r]));

  return Promise.all(
    memberIds.map(async (memberId): Promise<PushResult> => {
      const target = byId.get(memberId);
      if (!target) return { memberId, status: "skipped", reason: "unknown_member" };
      if (!target.apns_token) return { memberId, status: "skipped", reason: "no_device_token" };
      try {
        return await sendOne(env, { ...target, apns_token: target.apns_token }, payload);
      } catch (error) {
        return { memberId, status: "failed", reason: error instanceof Error ? error.name : "error" };
      }
    }),
  );
}
