// #67: the Rate Limiting binding counts per Cloudflare location and only roughly, so in production 23
// tries in a row never got a 429. The D1 counter here holds the contract "接続元ごとに60秒に5回まで"
// (docs/plan.md) on its own.

import { createExecutionContext, createScheduledController, waitOnExecutionContext } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import worker from "../src/index";
import { addressGroup, JOIN_ATTEMPTS_PER_WINDOW, JOIN_WINDOW_MS, takeJoinAttempt } from "../src/join-limit";
import { call, createFamily, invite, randomIp } from "./helpers";

/** The binding as production behaved in #67: it lets everything through. */
const leakyEnv = { ...env, JOIN_LIMITER: { limit: async () => ({ success: true }) } } as unknown as Env;

function joinWith(e: Env, code: string, ip: string, name = "x"): Promise<Response> {
  return call("POST", `/invites/${code}/join`, { body: { role: "family", display_name: name }, ip, env: e });
}

describe("takeJoinAttempt", () => {
  it("allows five attempts in a minute and refuses the sixth", async () => {
    const ip = randomIp();
    const now = Date.UTC(2026, 10, 7, 3, 0, 0);
    const results: boolean[] = [];
    for (let i = 0; i < 6; i++) results.push(await takeJoinAttempt(env, ip, now + i * 1000));
    expect(JOIN_ATTEMPTS_PER_WINDOW).toBe(5);
    expect(results).toEqual([true, true, true, true, true, false]);
  });

  it("starts counting again once the minute has passed", async () => {
    const ip = randomIp();
    const now = Date.UTC(2026, 10, 7, 3, 10, 0);
    for (let i = 0; i < 6; i++) await takeJoinAttempt(env, ip, now);
    expect(await takeJoinAttempt(env, ip, now + JOIN_WINDOW_MS - 1)).toBe(false);
    expect(await takeJoinAttempt(env, ip, now + JOIN_WINDOW_MS)).toBe(true);
  });

  it("lets exactly five of ten simultaneous attempts through", async () => {
    const ip = randomIp();
    const now = Date.UTC(2026, 10, 7, 3, 20, 0);
    const results = await Promise.all(Array.from({ length: 10 }, () => takeJoinAttempt(env, ip, now)));
    expect(results.filter(Boolean)).toHaveLength(5);
  });

  it("keeps each address apart", async () => {
    const now = Date.UTC(2026, 10, 7, 3, 30, 0);
    const a = randomIp();
    for (let i = 0; i < 6; i++) await takeJoinAttempt(env, a, now);
    expect(await takeJoinAttempt(env, a, now)).toBe(false);
    expect(await takeJoinAttempt(env, randomIp(), now)).toBe(true);
  });

  it("counts one IPv6 /64 as one address, since its owner can pick any address inside it", async () => {
    const now = Date.UTC(2026, 10, 7, 3, 40, 0);
    for (let i = 1; i <= 5; i++) expect(await takeJoinAttempt(env, `2001:db8:67:1::${i}`, now)).toBe(true);
    expect(await takeJoinAttempt(env, "2001:db8:67:1:ffff:1:2:3", now)).toBe(false);
    expect(await takeJoinAttempt(env, "2001:db8:67:2::1", now)).toBe(true);
  });

  it("stores neither the address nor a plain hash of it", async () => {
    const ip = "198.51.100.67";
    await takeJoinAttempt(env, ip, Date.UTC(2026, 10, 7, 3, 50, 0));
    const plain = Array.from(
      new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(ip))),
      (b) => b.toString(16).padStart(2, "0"),
    ).join("");
    const rows = await env.DB.prepare("SELECT key FROM join_attempts").all<{ key: string }>();
    expect(rows.results.length).toBeGreaterThan(0);
    for (const { key } of rows.results) {
      expect(key).not.toContain(ip);
      expect(key).not.toContain("198.51.100");
      expect(key).not.toBe(plain);
      expect(key).toMatch(/^[0-9a-f]{64}$/);
    }
  });
});

describe("addressGroup", () => {
  it("keeps IPv4 whole and cuts IPv6 to its first 64 bits", () => {
    expect(addressGroup("203.0.113.9")).toBe("203.0.113.9");
    expect(addressGroup("2001:DB8:0:1:2:3:4:5")).toBe("2001:db8:0:1::/64");
    expect(addressGroup("2001:db8::1")).toBe("2001:db8:0:0::/64");
    expect(addressGroup("::1")).toBe("0:0:0:0::/64");
    expect(addressGroup("unknown")).toBe("unknown");
  });
});

describe("POST /invites/{code}/join when the binding lets everything through", () => {
  it("still answers 429 from the sixth try in a minute, malformed codes included", async () => {
    const ip = randomIp();
    const statuses: number[] = [];
    for (let i = 0; i < 6; i++) statuses.push((await joinWith(leakyEnv, i % 2 ? "x" : String(200000 + i), ip)).status);
    expect(statuses).toEqual([404, 404, 404, 404, 404, 429]);
  });

  it("refuses even the right code from that address, and lets the family in from another", async () => {
    const family = await createFamily();
    const ip = randomIp();
    for (let i = 0; i < 5; i++) await joinWith(leakyEnv, String(300000 + i), ip);
    const { code } = await invite(family.deviceKey);
    expect((await joinWith(leakyEnv, code, ip, "妹")).status).toBe(429);
    expect((await joinWith(leakyEnv, code, randomIp(), "妹")).status).toBe(201);
  });

  it("lets the mother in on her first try", async () => {
    const family = await createFamily();
    const { code } = await invite(family.deviceKey);
    expect((await joinWith(leakyEnv, code, randomIp(), "母")).status).toBe(201);
  });
});

describe("cleanup", () => {
  it("deletes attempt rows older than a day at the daily cleanup", async () => {
    const cleanupTick = Date.UTC(2026, 10, 6, 19, 0, 0);
    const oldIp = randomIp();
    const newIp = randomIp();
    await takeJoinAttempt(env, oldIp, cleanupTick - 25 * 3600_000);
    await takeJoinAttempt(env, newIp, cleanupTick - 3600_000);
    const before = (await env.DB.prepare("SELECT count(*) AS n FROM join_attempts WHERE window_start < ?")
      .bind(cleanupTick - 24 * 3600_000)
      .first<{ n: number }>())!.n;
    expect(before).toBeGreaterThan(0);

    const ctx = createExecutionContext();
    await worker.scheduled(createScheduledController({ scheduledTime: cleanupTick, cron: "*/5 * * * *" }), env, ctx);
    await waitOnExecutionContext(ctx);

    const old = await env.DB.prepare("SELECT count(*) AS n FROM join_attempts WHERE window_start < ?")
      .bind(cleanupTick - 24 * 3600_000)
      .first<{ n: number }>();
    expect(old?.n).toBe(0);
    const recent = await env.DB.prepare("SELECT count(*) AS n FROM join_attempts WHERE window_start = ?")
      .bind(cleanupTick - 3600_000)
      .first<{ n: number }>();
    expect(recent?.n).toBeGreaterThan(0);
  });
});
