// The daily caps on Claude per family, and the per-address cap on POST /families (the public-release
// audit of 2026-11-07, point 1). Without them, anyone could make a family, join it as the mother, and
// call Claude through /consult and /page as often as they liked. The judge queue, the consultation,
// and the research are checked in their own test files; this one holds the counters themselves.

import { createExecutionContext, createScheduledController, waitOnExecutionContext } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import worker from "../src/index";
import {
  CLAUDE_CALLS_PER_FAMILY_DAY,
  RESEARCH_STARTS_PER_FAMILY_DAY,
  takeClaudeCall,
  takeResearchStart,
} from "../src/claude-limit";
import { FAMILY_CREATE_WINDOW_MS, FAMILY_CREATES_PER_WINDOW, takeFamilyCreate } from "../src/family-limit";
import { jstDate } from "../src/time";
import { call, randomIp } from "./helpers";

// 12:00 JST on 2026-11-07.
const NOON_JST = Date.UTC(2026, 10, 7, 3, 0, 0);

async function counts(familyId: string, day: string) {
  return env.DB.prepare("SELECT claude_calls, research_starts FROM claude_daily WHERE family_id = ? AND day = ?")
    .bind(familyId, day)
    .first<{ claude_calls: number; research_starts: number }>();
}

describe("the caps", () => {
  it("are 200 Claude calls and 20 research starts a family a day", () => {
    // Written out, so a change to the numbers is a change to this test and to docs/design.md too.
    expect(CLAUDE_CALLS_PER_FAMILY_DAY).toBe(200);
    expect(RESEARCH_STARTS_PER_FAMILY_DAY).toBe(20);
    expect(FAMILY_CREATES_PER_WINDOW).toBe(5);
    expect(FAMILY_CREATE_WINDOW_MS).toBe(3600_000);
  });
});

describe("takeClaudeCall", () => {
  it("allows calls up to the cap and refuses the next, without counting the refused one", async () => {
    const familyId = crypto.randomUUID();
    const results: boolean[] = [];
    for (let i = 0; i < 4; i++) results.push(await takeClaudeCall(env, familyId, NOON_JST, 3));
    expect(results).toEqual([true, true, true, false]);
    expect(await counts(familyId, "2026-11-07")).toEqual({ claude_calls: 3, research_starts: 0 });
  });

  it("lets exactly the cap through of many simultaneous calls", async () => {
    const familyId = crypto.randomUUID();
    const results = await Promise.all(Array.from({ length: 10 }, () => takeClaudeCall(env, familyId, NOON_JST, 4)));
    expect(results.filter(Boolean)).toHaveLength(4);
  });

  it("keeps each family apart", async () => {
    const a = crypto.randomUUID();
    await takeClaudeCall(env, a, NOON_JST, 1);
    expect(await takeClaudeCall(env, a, NOON_JST, 1)).toBe(false);
    expect(await takeClaudeCall(env, crypto.randomUUID(), NOON_JST, 1)).toBe(true);
  });

  it("starts again at midnight JST, not at midnight UTC", async () => {
    const familyId = crypto.randomUUID();
    // 23:59 JST on 2026-11-07 is 14:59 UTC the same day; 00:00 JST on the 8th is 15:00 UTC on the 7th.
    const beforeMidnight = Date.UTC(2026, 10, 7, 14, 59, 0);
    const afterMidnight = Date.UTC(2026, 10, 7, 15, 0, 0);
    expect(await takeClaudeCall(env, familyId, beforeMidnight, 1)).toBe(true);
    expect(await takeClaudeCall(env, familyId, beforeMidnight, 1)).toBe(false);
    expect(await takeClaudeCall(env, familyId, afterMidnight, 1)).toBe(true);
    expect(jstDate(afterMidnight)).toBe("2026-11-08");
  });

  it("uses the default cap of 200", async () => {
    const familyId = crypto.randomUUID();
    await env.DB.prepare("INSERT INTO claude_daily (family_id, day, claude_calls, research_starts) VALUES (?, ?, ?, 0)")
      .bind(familyId, "2026-11-07", CLAUDE_CALLS_PER_FAMILY_DAY - 1)
      .run();
    expect(await takeClaudeCall(env, familyId, NOON_JST)).toBe(true);
    expect(await takeClaudeCall(env, familyId, NOON_JST)).toBe(false);
  });

  it("answers no call, and does not throw, when D1 fails, so the caller answers with the rules", async () => {
    const broken = {
      ...env,
      DB: {
        prepare: () => {
          throw new Error("D1 down");
        },
      },
    } as unknown as Env;
    await expect(takeClaudeCall(broken, crypto.randomUUID(), NOON_JST)).resolves.toBe(false);
    await expect(takeResearchStart(broken, crypto.randomUUID(), NOON_JST)).resolves.toBe(false);
  });
});

describe("takeResearchStart", () => {
  it("counts apart from the Claude calls", async () => {
    const familyId = crypto.randomUUID();
    await takeClaudeCall(env, familyId, NOON_JST, 1);
    expect(await takeClaudeCall(env, familyId, NOON_JST, 1)).toBe(false);
    expect(await takeResearchStart(env, familyId, NOON_JST, 2)).toBe(true);
    expect(await takeResearchStart(env, familyId, NOON_JST, 2)).toBe(true);
    expect(await takeResearchStart(env, familyId, NOON_JST, 2)).toBe(false);
    expect(await counts(familyId, "2026-11-07")).toEqual({ claude_calls: 1, research_starts: 2 });
  });

  it("uses the default cap of 20", async () => {
    const familyId = crypto.randomUUID();
    await env.DB.prepare("INSERT INTO claude_daily (family_id, day, claude_calls, research_starts) VALUES (?, ?, 0, ?)")
      .bind(familyId, "2026-11-07", RESEARCH_STARTS_PER_FAMILY_DAY - 1)
      .run();
    expect(await takeResearchStart(env, familyId, NOON_JST)).toBe(true);
    expect(await takeResearchStart(env, familyId, NOON_JST)).toBe(false);
  });
});

describe("takeFamilyCreate", () => {
  it("allows five families an hour from one address and refuses the sixth", async () => {
    const ip = randomIp();
    const results: boolean[] = [];
    for (let i = 0; i < 6; i++) results.push(await takeFamilyCreate(env, ip, NOON_JST + i * 1000));
    expect(results).toEqual([true, true, true, true, true, false]);
  });

  it("starts counting again once the hour has passed", async () => {
    const ip = randomIp();
    for (let i = 0; i < 6; i++) await takeFamilyCreate(env, ip, NOON_JST);
    expect(await takeFamilyCreate(env, ip, NOON_JST + FAMILY_CREATE_WINDOW_MS - 1)).toBe(false);
    expect(await takeFamilyCreate(env, ip, NOON_JST + FAMILY_CREATE_WINDOW_MS)).toBe(true);
  });

  it("keeps each address apart, and an IPv6 home line counts as one", async () => {
    const a = randomIp();
    for (let i = 0; i < 5; i++) await takeFamilyCreate(env, a, NOON_JST);
    expect(await takeFamilyCreate(env, a, NOON_JST)).toBe(false);
    expect(await takeFamilyCreate(env, randomIp(), NOON_JST)).toBe(true);

    for (let i = 0; i < 5; i++) await takeFamilyCreate(env, `2001:db8:77::${i + 1}`, NOON_JST);
    expect(await takeFamilyCreate(env, "2001:db8:77:ffff::9", NOON_JST)).toBe(false);
  });

  it("lets exactly five of ten simultaneous tries through", async () => {
    const ip = randomIp();
    const results = await Promise.all(Array.from({ length: 10 }, () => takeFamilyCreate(env, ip, NOON_JST)));
    expect(results.filter(Boolean)).toHaveLength(5);
  });

  it("does not share its count with the joins of the same address", async () => {
    const ip = randomIp();
    for (let i = 0; i < 5; i++) await takeFamilyCreate(env, ip, NOON_JST);
    const joins = await env.DB.prepare("SELECT count(*) AS n FROM join_attempts").first<{ n: number }>();
    const before = joins?.n ?? 0;
    expect(await takeFamilyCreate(env, ip, NOON_JST)).toBe(false);
    const after = await env.DB.prepare("SELECT count(*) AS n FROM join_attempts").first<{ n: number }>();
    expect(after?.n ?? 0).toBe(before);
  });
});

describe("POST /families", () => {
  it("answers 429 to the sixth family from one address in an hour, and makes no family for it", async () => {
    const ip = randomIp();
    const statuses: number[] = [];
    for (let i = 0; i < 6; i++) {
      statuses.push((await call("POST", "/families", { body: { display_name: "x" }, ip })).status);
    }
    expect(statuses).toEqual([201, 201, 201, 201, 201, 429]);

    const before = await env.DB.prepare("SELECT count(*) AS n FROM families").first<{ n: number }>();
    const refused = await call("POST", "/families", { body: { display_name: "x" }, ip });
    expect(refused.status).toBe(429);
    expect(await refused.json()).toMatchObject({ error: "too_many_attempts" });
    const after = await env.DB.prepare("SELECT count(*) AS n FROM families").first<{ n: number }>();
    expect(after?.n).toBe(before?.n);

    // Another address, as the next judge's phone would be, still makes one.
    expect((await call("POST", "/families", { body: { display_name: "x" }, ip: randomIp() })).status).toBe(201);
  });
});

describe("cleanup", () => {
  it("keeps today's and yesterday's counts and old family tries go after a day", async () => {
    // 04:00 JST on 2026-11-08, when the daily cleanup runs.
    const cleanupTick = Date.UTC(2026, 10, 7, 19, 0, 0);
    const familyId = crypto.randomUUID();
    for (const day of ["2026-11-06", "2026-11-07", "2026-11-08"]) {
      await env.DB.prepare(
        "INSERT INTO claude_daily (family_id, day, claude_calls, research_starts) VALUES (?, ?, 1, 0)",
      )
        .bind(familyId, day)
        .run();
    }
    const oldIp = randomIp();
    const newIp = randomIp();
    await takeFamilyCreate(env, oldIp, cleanupTick - 25 * 3600_000);
    await takeFamilyCreate(env, newIp, cleanupTick - 3600_000);

    const ctx = createExecutionContext();
    await worker.scheduled(createScheduledController({ scheduledTime: cleanupTick, cron: "*/5 * * * *" }), env, ctx);
    await waitOnExecutionContext(ctx);

    const days = await env.DB.prepare("SELECT day FROM claude_daily WHERE family_id = ? ORDER BY day")
      .bind(familyId)
      .all<{ day: string }>();
    expect(days.results.map((r) => r.day)).toEqual(["2026-11-07", "2026-11-08"]);
    const old = await env.DB.prepare("SELECT count(*) AS n FROM family_attempts WHERE window_start < ?")
      .bind(cleanupTick - 24 * 3600_000)
      .first<{ n: number }>();
    expect(old?.n).toBe(0);
    const recent = await env.DB.prepare("SELECT count(*) AS n FROM family_attempts WHERE window_start = ?")
      .bind(cleanupTick - 3600_000)
      .first<{ n: number }>();
    expect(recent?.n).toBeGreaterThan(0);
  });
});
