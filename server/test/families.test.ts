import { env } from "cloudflare:workers";
import { afterEach, describe, expect, it, vi } from "vitest";
import { call, createFamily, invite, join } from "./helpers";

afterEach(() => {
  vi.useRealTimers();
});

describe("POST /families", () => {
  it("makes the caller the first member with the family role", async () => {
    const created = await createFamily("作者");

    expect(created.role).toBe("family");
    expect(created.familyId).toMatch(/^[0-9a-f-]{36}$/);
    expect(created.familyToken).toMatch(/^[A-Za-z0-9_-]{32}$/);
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
    const joined = (await res.json()) as { deviceKey: string; familyId: string; role: string };
    expect(joined.familyId).toBe(family.familyId);
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
