import { env } from "cloudflare:workers";
import { http, HttpResponse } from "msw";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { ExternalBudget } from "../src/budget";
import { resetApnsJwtCache, sendPush } from "../src/push";
import { createFamily } from "./helpers";
import { network } from "./network";

const SANDBOX = "https://api.sandbox.push.apple.com";
const PRODUCTION = "https://api.push.apple.com";

let pushEnv: Env;
let publicKey: CryptoKey;

function toPem(der: ArrayBuffer): string {
  const b64 = btoa(String.fromCharCode(...new Uint8Array(der)));
  return `-----BEGIN PRIVATE KEY-----\n${b64.match(/.{1,64}/g)?.join("\n")}\n-----END PRIVATE KEY-----`;
}

function fromB64url(part: string): Uint8Array {
  const b64 = part.replace(/-/g, "+").replace(/_/g, "/");
  return Uint8Array.from(atob(b64 + "=".repeat((4 - (b64.length % 4)) % 4)), (c) => c.charCodeAt(0));
}

function decodeJwt(jwt: string) {
  const [h, c, s] = jwt.split(".");
  return {
    header: JSON.parse(new TextDecoder().decode(fromB64url(h ?? ""))) as Record<string, unknown>,
    claims: JSON.parse(new TextDecoder().decode(fromB64url(c ?? ""))) as Record<string, unknown>,
    signingInput: `${h}.${c}`,
    signature: fromB64url(s ?? ""),
  };
}

async function newP8(): Promise<string> {
  const pair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign"])) as CryptoKeyPair;
  return toPem((await crypto.subtle.exportKey("pkcs8", pair.privateKey)) as ArrayBuffer);
}

beforeAll(async () => {
  // A throwaway P-256 key stands in for the .p8 from Apple.
  const pair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, [
    "sign",
    "verify",
  ])) as CryptoKeyPair;
  publicKey = pair.publicKey;
  const pkcs8 = (await crypto.subtle.exportKey("pkcs8", pair.privateKey)) as ArrayBuffer;
  pushEnv = { ...env, APNS_KEY_P8: toPem(pkcs8) };
});

beforeEach(() => {
  resetApnsJwtCache();
});

afterEach(() => {
  vi.useRealTimers();
});

async function memberWithToken(token: string | null, apnsEnv: "sandbox" | "production" = "sandbox") {
  const family = await createFamily();
  await env.DB.prepare("UPDATE members SET apns_token = ?, apns_env = ? WHERE id = ?")
    .bind(token, token === null ? null : apnsEnv, family.memberId)
    .run();
  return family.memberId;
}

/** Records the requests APNs receives and answers 200. */
function captureApns() {
  const seen: Array<{ url: string; headers: Headers; body: unknown }> = [];
  const handler: Parameters<typeof http.post>[1] = async ({ request }) => {
    seen.push({ url: request.url, headers: request.headers, body: await request.json() });
    return new HttpResponse(null, { status: 200, headers: { "apns-id": crypto.randomUUID() } });
  };
  network.use(http.post(`${SANDBOX}/3/device/:token`, handler), http.post(`${PRODUCTION}/3/device/:token`, handler));
  return seen;
}

describe("sendPush", () => {
  it("signs the APNs token with ES256 using the key id and team id", async () => {
    const seen = captureApns();
    const memberId = await memberWithToken("aa".repeat(32));
    const now = Date.now();

    const results = await sendPush(pushEnv, [memberId], { title: "見守り", body: "確かめてください" }, new ExternalBudget());
    expect(results).toEqual([{ memberId, status: "sent", httpStatus: 200 }]);

    const auth = seen[0]?.headers.get("authorization") ?? "";
    expect(auth).toMatch(/^bearer /);
    const jwt = decodeJwt(auth.slice("bearer ".length));
    expect(jwt.header).toEqual({ alg: "ES256", kid: env.APNS_KEY_ID });
    expect(jwt.claims.iss).toBe(env.APNS_TEAM_ID);
    expect(Math.abs(Number(jwt.claims.iat) - now / 1000)).toBeLessThan(5);
    const valid = await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      publicKey,
      jwt.signature,
      new TextEncoder().encode(jwt.signingInput),
    );
    expect(valid).toBe(true);
  });

  it("reuses the token for 50 minutes and makes a new one after that", async () => {
    const seen = captureApns();
    const memberId = await memberWithToken("bb".repeat(32));
    const start = Date.now();
    vi.useFakeTimers({ toFake: ["Date"] });
    const tokenAt = async (offsetMs: number) => {
      vi.setSystemTime(start + offsetMs);
      await sendPush(pushEnv, [memberId], { title: "t", body: "b" }, new ExternalBudget());
      return seen.at(-1)?.headers.get("authorization");
    };

    const first = await tokenAt(0);
    expect(await tokenAt(49 * 60_000)).toBe(first);
    const rebuilt = await tokenAt(50 * 60_000 + 1000);
    expect(rebuilt).not.toBe(first);
    expect(Number(decodeJwt((rebuilt ?? "").slice(7)).claims.iat)).toBe(Math.floor((start + 50 * 60_000 + 1000) / 1000));
    // The new token is reused in turn.
    expect(await tokenAt(60 * 60_000)).toBe(rebuilt);
  });

  it("does not rebuild the token within 20 minutes after APNs rejects it, unless the key changed", async () => {
    const memberId = await memberWithToken("9a".repeat(32));
    const auths: string[] = [];
    network.use(
      http.post(`${SANDBOX}/3/device/:token`, ({ request }) => {
        auths.push(request.headers.get("authorization") ?? "");
        return HttpResponse.json({ reason: "ExpiredProviderToken" }, { status: 403 });
      }),
    );
    const start = Date.now();
    vi.useFakeTimers({ toFake: ["Date"] });
    const sendAt = async (offsetMs: number, e: Env = pushEnv) => {
      vi.setSystemTime(start + offsetMs);
      await sendPush(e, [memberId], { title: "t", body: "b" }, new ExternalBudget());
      return auths.at(-1);
    };

    const first = await sendAt(0);
    // Rejected, but rebuilding now would count as a refresh within 20 minutes.
    expect(await sendAt(60_000)).toBe(first);
    expect(await sendAt(19 * 60_000)).toBe(first);
    const second = await sendAt(20 * 60_000 + 1000);
    expect(second).not.toBe(first);
    expect(await sendAt(21 * 60_000)).toBe(second);

    // A different key is a different token stream, so it signs at once.
    const otherKey = await newP8();
    const third = await sendAt(22 * 60_000, { ...pushEnv, APNS_KEY_P8: otherKey, APNS_KEY_ID: "OTHERKEY12" });
    expect(third).not.toBe(second);
    expect(decodeJwt((third ?? "").slice(7)).header.kid).toBe("OTHERKEY12");
  });

  it("skips members without a device token and sends to the rest", async () => {
    const seen = captureApns();
    const withToken = await memberWithToken("cc".repeat(32));
    const without = await memberWithToken(null);

    const results = await sendPush(pushEnv, [without, withToken], { title: "t", body: "b" }, new ExternalBudget());
    expect(results).toEqual([
      { memberId: without, status: "skipped", reason: "no_device_token" },
      { memberId: withToken, status: "sent", httpStatus: 200 },
    ]);
    expect(seen).toHaveLength(1);
  });

  it("picks the sandbox or production host from each member's apns_env", async () => {
    const seen = captureApns();
    const dev = await memberWithToken("dd".repeat(32), "sandbox");
    const prod = await memberWithToken("ee".repeat(32), "production");

    await sendPush(pushEnv, [dev, prod], { title: "t", body: "b" }, new ExternalBudget());
    expect(seen.map((s) => s.url).sort()).toEqual([
      `${PRODUCTION}/3/device/${"ee".repeat(32)}`,
      `${SANDBOX}/3/device/${"dd".repeat(32)}`,
    ]);
    // Sent at the same time, both carry one shared token rather than two fresh ones.
    expect(seen[0]?.headers.get("authorization")).toBe(seen[1]?.headers.get("authorization"));
  });

  it("sends an alert with the topic and the payload's data", async () => {
    const seen = captureApns();
    const memberId = await memberWithToken("ff".repeat(32));

    await sendPush(pushEnv, [memberId], { title: "見守り", body: "本文", data: { caseId: "c1" }, threadId: "case-c1" }, new ExternalBudget());
    const request = seen[0];
    expect(request?.headers.get("apns-topic")).toBe(env.APNS_TOPIC);
    expect(request?.headers.get("apns-push-type")).toBe("alert");
    expect(request?.body).toEqual({
      aps: { alert: { title: "見守り", body: "本文" }, sound: "default", "thread-id": "case-c1" },
      caseId: "c1",
    });
  });

  it("forgets a device token that APNs says is no longer registered", async () => {
    const memberId = await memberWithToken("ab".repeat(32));
    network.use(
      http.post(`${SANDBOX}/3/device/:token`, () => HttpResponse.json({ reason: "Unregistered" }, { status: 410 })),
    );

    const results = await sendPush(pushEnv, [memberId], { title: "t", body: "b" }, new ExternalBudget());
    expect(results).toEqual([{ memberId, status: "failed", httpStatus: 410, reason: "Unregistered" }]);
    const row = await env.DB.prepare("SELECT apns_token FROM members WHERE id = ?").bind(memberId).first();
    expect(row).toEqual({ apns_token: null });
  });

  it("takes one ticket of the shared budget per device it sends to", async () => {
    const seen = captureApns();
    const a = await memberWithToken("a1".repeat(32));
    const b = await memberWithToken("b1".repeat(32));
    const none = await memberWithToken(null);
    const budget = new ExternalBudget(5);

    await sendPush(pushEnv, [a, none, b], { title: "t", body: "b" }, budget);
    expect(seen).toHaveLength(2);
    expect(budget.remaining).toBe(3);
  });

  it("sends to nobody when the budget cannot cover every device, so a notice is not split", async () => {
    const seen = captureApns();
    const a = await memberWithToken("a2".repeat(32));
    const b = await memberWithToken("b2".repeat(32));
    const budget = new ExternalBudget(1);

    const results = await sendPush(pushEnv, [a, b], { title: "t", body: "b" }, budget);
    expect(results).toEqual([
      { memberId: a, status: "skipped", reason: "no_budget" },
      { memberId: b, status: "skipped", reason: "no_budget" },
    ]);
    expect(seen).toHaveLength(0);
    expect(budget.remaining).toBe(1);
  });

  it("reports a member that does not exist instead of throwing", async () => {
    const results = await sendPush(pushEnv, ["no-such-member"], { title: "t", body: "b" }, new ExternalBudget());
    expect(results).toEqual([{ memberId: "no-such-member", status: "skipped", reason: "unknown_member" }]);
  });
});
