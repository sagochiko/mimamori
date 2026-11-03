import { env } from "cloudflare:workers";
import { http, HttpResponse } from "msw";
import { afterEach, describe, expect, it, vi } from "vitest";
import { resetApnsJwtCache } from "../src/push";
import { call, createFamily, invite, join, randomIp } from "./helpers";
import { network } from "./network";

afterEach(() => {
  vi.useRealTimers();
});

describe("POST /families", () => {
  it("makes the caller the first member with the family role", async () => {
    const created = await createFamily("作者");

    expect(created.role).toBe("family");
    expect(created.familyId).toMatch(/^[0-9a-f-]{36}$/);
    // 128 bits as 32 lowercase hex digits: Cloudflare's log redaction hides runs of 32+ hex digits.
    expect(created.familyToken).toMatch(/^[0-9a-f]{32}$/);
    expect(created.deviceKey.length).toBeGreaterThanOrEqual(43);

    const row = await env.DB.prepare("SELECT role, display_name, family_id FROM members WHERE id = ?")
      .bind(created.memberId)
      .first<{ role: string; display_name: string; family_id: string }>();
    expect(row).toEqual({ role: "family", display_name: "作者", family_id: created.familyId });
  });

  it("stores only a hash of the device key", async () => {
    const created = await createFamily();
    const row = await env.DB.prepare("SELECT device_key_hash FROM members WHERE id = ?")
      .bind(created.memberId)
      .first<{ device_key_hash: string }>();
    expect(row?.device_key_hash).toMatch(/^[0-9a-f]{64}$/);
    expect(row?.device_key_hash).not.toContain(created.deviceKey);
  });
});

describe("invites", () => {
  it("gives a 6-digit code that lasts 24 hours", async () => {
    const family = await createFamily();
    const before = Date.now();
    const { code, expiresAt } = await invite(family.deviceKey);

    expect(code).toMatch(/^\d{6}$/);
    const lifetime = Date.parse(expiresAt) - before;
    expect(lifetime).toBeGreaterThan(24 * 3600_000 - 60_000);
    expect(lifetime).toBeLessThanOrEqual(24 * 3600_000 + 60_000);
  });

  it("lets someone join with the code and returns a device key", async () => {
    const family = await createFamily();
    const { code } = await invite(family.deviceKey);

    const res = await join(code, "protected", "母");
    expect(res.status).toBe(201);
    const joined = (await res.json()) as { deviceKey: string; familyId: string; role: string; familyToken: string };
    expect(joined.familyId).toBe(family.familyId);
    // The protected person's phone needs it for the SMS and DNS addresses.
    expect(joined.familyToken).toBe(family.familyToken);
    expect(joined.role).toBe("protected");
    expect(joined.deviceKey.length).toBeGreaterThanOrEqual(43);
    expect(joined.deviceKey).not.toBe(family.deviceKey);

    // The new key works for calls that need a member.
    const again = await call("POST", "/invites", { deviceKey: joined.deviceKey });
    expect(again.status).toBe(201);
  });

  it("does not accept the same code twice", async () => {
    const family = await createFamily();
    const { code } = await invite(family.deviceKey);

    expect((await join(code, "protected", "母")).status).toBe(201);
    const second = await join(code, "family", "妹");
    expect(second.status).toBe(404);
    expect(await second.json()).not.toHaveProperty("deviceKey");
  });

  it("lets only one of two simultaneous joins with the same code in", async () => {
    const family = await createFamily();
    const { code } = await invite(family.deviceKey);

    const results = await Promise.all([join(code, "protected", "母"), join(code, "family", "妹")]);
    expect(results.map((r) => r.status).sort()).toEqual([201, 404]);
    const members = await env.DB.prepare("SELECT COUNT(*) AS n FROM members WHERE family_id = ?")
      .bind(family.familyId)
      .first<{ n: number }>();
    expect(members?.n).toBe(2);
  });

  it("gives the family token to a family-role joiner too", async () => {
    const family = await createFamily();
    const { code } = await invite(family.deviceKey);
    const joined = (await (await join(code, "family", "妹")).json()) as { familyToken: string };
    expect(joined.familyToken).toBe(family.familyToken);
  });

  it("does not accept a code after 24 hours", async () => {
    const family = await createFamily();
    const { code } = await invite(family.deviceKey);

    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(Date.now() + 24 * 3600_000 + 1000);

    const res = await join(code, "protected", "母");
    expect(res.status).toBe(404);
  });

  it("rejects a role outside protected and family", async () => {
    const family = await createFamily();
    const { code } = await invite(family.deviceKey);
    const res = await call("POST", `/invites/${code}/join`, {
      body: { role: "admin", display_name: "x" },
    });
    expect(res.status).toBe(400);
  });
});

describe("join rate limit", () => {
  it("answers 429 once one address tries too many codes, and other addresses still get in", async () => {
    const family = await createFamily();
    const ip = randomIp();
    const statuses: number[] = [];
    for (let i = 0; i < 6; i++) {
      statuses.push((await join(String(100000 + i), "family", "x", ip)).status);
    }
    expect(statuses.slice(0, 5)).toEqual([404, 404, 404, 404, 404]);
    expect(statuses[5]).toBe(429);

    const { code } = await invite(family.deviceKey);
    expect((await join(code, "family", "妹", ip)).status).toBe(429);
    expect((await join(code, "family", "妹", randomIp())).status).toBe(201);
  });
});

describe("join notification", () => {
  it("tells every existing member who joined, and not the joiner", async () => {
    resetApnsJwtCache();
    const owner = await createFamily("作者");
    const { code: first } = await invite(owner.deviceKey);
    const sister = (await (await join(first, "family", "妹")).json()) as { memberId: string };
    const p8 = await testP8();
    const pushEnv = { ...env, APNS_KEY_P8: p8 };
    for (const [id, token] of [
      [owner.memberId, "a1".repeat(32)],
      [sister.memberId, "b2".repeat(32)],
    ] as const) {
      await env.DB.prepare("UPDATE members SET apns_token = ?, apns_env = 'sandbox' WHERE id = ?").bind(token, id).run();
    }

    const sent: Array<{ token: string; body: unknown }> = [];
    network.use(
      http.post("https://api.sandbox.push.apple.com/3/device/:token", async ({ request, params }) => {
        sent.push({ token: String(params.token), body: await request.json() });
        return new HttpResponse(null, { status: 200 });
      }),
    );

    const { code } = await invite(owner.deviceKey);
    const res = await call("POST", `/invites/${code}/join`, {
      body: { role: "protected", display_name: "母" },
      ip: randomIp(),
      env: pushEnv,
    });
    expect(res.status).toBe(201);

    expect(sent.map((s) => s.token).sort()).toEqual(["a1".repeat(32), "b2".repeat(32)]);
    for (const s of sent) expect(s.body).toEqual({ aps: { alert: { body: "母が入りました" }, sound: "default" } });
  });
});

async function testP8(): Promise<string> {
  const pair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign"])) as CryptoKeyPair;
  const der = (await crypto.subtle.exportKey("pkcs8", pair.privateKey)) as ArrayBuffer;
  return `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...new Uint8Array(der)))}\n-----END PRIVATE KEY-----`;
}

describe("device key", () => {
  it("returns 401 without a device key", async () => {
    expect((await call("POST", "/invites")).status).toBe(401);
  });

  it("returns 401 with an unknown device key", async () => {
    expect((await call("POST", "/invites", { deviceKey: "not-a-real-key" })).status).toBe(401);
  });

  it("registers an APNs token for the caller", async () => {
    const family = await createFamily();
    const res = await call("PUT", "/members/me/apns", {
      deviceKey: family.deviceKey,
      body: { token: "ab".repeat(32), env: "sandbox" },
    });
    expect(res.status).toBe(204);
    const row = await env.DB.prepare("SELECT apns_token, apns_env FROM members WHERE id = ?")
      .bind(family.memberId)
      .first();
    expect(row).toEqual({ apns_token: "ab".repeat(32), apns_env: "sandbox" });
  });
});
