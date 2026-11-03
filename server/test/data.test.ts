// "データの扱い" in docs/design.md: leaving, "delete everything", and the 30-day cleanup.

import { createExecutionContext, createScheduledController, waitOnExecutionContext } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { http, HttpResponse } from "msw";
import { describe, expect, it } from "vitest";
import { dueJobs, JOBS } from "../src/cron";
import worker from "../src/index";
import { sealText } from "../src/secretbox";
import { call, createFamily, invite, join, type Created } from "./helpers";
import { network } from "./network";

const DAY = 24 * 3600_000;
const FAMILY_TABLES = ["members", "invites", "alerts", "cases", "smiles", "gmail_auth"] as const;

async function joinAs(owner: Created, role: "protected" | "family", name: string) {
  const { code } = await invite(owner.deviceKey);
  const res = await join(code, role, name);
  return (await res.json()) as { memberId: string; deviceKey: string };
}

/** Puts one row in every table for the family, plus a photo in R2. */
async function seed(family: Created, opts: { at?: number; sessionId?: string; refreshToken?: string } = {}) {
  const at = opts.at ?? Date.now();
  const alertId = crypto.randomUUID();
  const caseId = crypto.randomUUID();
  const smileId = crypto.randomUUID();
  const r2Key = `${family.familyId}/smiles/${smileId}.jpg`;
  const statements = [
    env.DB.prepare(
      "INSERT INTO alerts (id, family_id, source, level, reasons, summary, created_at) VALUES (?, ?, 'sms', 1, '[]', 'x', ?)",
    ).bind(alertId, family.familyId, at),
    env.DB.prepare(
      "INSERT INTO cases (id, family_id, alert_id, state, agent_session_id, notified_at) VALUES (?, ?, ?, 'notified', ?, ?)",
    ).bind(caseId, family.familyId, alertId, opts.sessionId ?? null, at),
    env.DB.prepare(
      "INSERT INTO relays (id, case_id, from_member_id, body, created_at) VALUES (?, ?, ?, 'x', ?)",
    ).bind(crypto.randomUUID(), caseId, family.memberId, at),
    env.DB.prepare(
      "INSERT INTO smiles (id, family_id, member_id, r2_key, score, created_at) VALUES (?, ?, ?, ?, 0.9, ?)",
    ).bind(smileId, family.familyId, family.memberId, r2Key, at),
  ];
  if (opts.refreshToken !== undefined) {
    statements.push(
      env.DB.prepare(
        "INSERT INTO gmail_auth (family_id, refresh_token_enc, granted_at) VALUES (?, ?, ?)",
      ).bind(family.familyId, await sealText(env.TOKEN_ENC_KEY, opts.refreshToken), at),
    );
  }
  await env.DB.batch(statements);
  await env.PHOTOS.put(r2Key, "jpeg-bytes");
  return { alertId, caseId, smileId, r2Key };
}

/** Many old cases, each with its own agent session. */
async function seedSessions(family: Created, count: number, at: number): Promise<string[]> {
  const ids = Array.from({ length: count }, (_, i) => `sesn_bulk_${i}_${crypto.randomUUID().slice(0, 8)}`);
  await env.DB.batch(
    ids.map((sessionId) =>
      env.DB.prepare(
        "INSERT INTO cases (id, family_id, state, agent_session_id, notified_at) VALUES (?, ?, 'notified', ?, ?)",
      ).bind(crypto.randomUUID(), family.familyId, sessionId, at),
    ),
  );
  return ids;
}

async function tick(scheduledTime: number): Promise<void> {
  const ctx = createExecutionContext();
  await worker.scheduled(createScheduledController({ scheduledTime, cron: "*/5 * * * *" }), env, ctx);
  await waitOnExecutionContext(ctx);
}

async function countFor(familyId: string): Promise<Record<string, number>> {
  const counts: Record<string, number> = {};
  for (const table of FAMILY_TABLES) {
    const row = await env.DB.prepare(`SELECT COUNT(*) AS n FROM ${table} WHERE family_id = ?`)
      .bind(familyId)
      .first<{ n: number }>();
    counts[table] = row?.n ?? -1;
  }
  const relays = await env.DB.prepare(
    "SELECT COUNT(*) AS n FROM relays WHERE case_id IN (SELECT id FROM cases WHERE family_id = ?)",
  )
    .bind(familyId)
    .first<{ n: number }>();
  counts.relays = relays?.n ?? -1;
  const families = await env.DB.prepare("SELECT COUNT(*) AS n FROM families WHERE id = ?")
    .bind(familyId)
    .first<{ n: number }>();
  counts.families = families?.n ?? -1;
  return counts;
}

async function r2Count(prefix: string): Promise<number> {
  return (await env.PHOTOS.list({ prefix })).objects.length;
}

describe("leaving the family", () => {
  it("makes the leaver's device key return 401 from the next call", async () => {
    const owner = await createFamily("作者");
    const sister = await joinAs(owner, "family", "妹");

    const res = await call("DELETE", `/members/${sister.memberId}`, { deviceKey: sister.deviceKey });
    expect(res.status).toBe(204);

    expect((await call("POST", "/invites", { deviceKey: sister.deviceKey })).status).toBe(401);
    expect((await call("POST", "/invites", { deviceKey: owner.deviceKey })).status).toBe(201);
  });

  it("accepts /members/me as the caller", async () => {
    const owner = await createFamily();
    const res = await call("DELETE", "/members/me", { deviceKey: owner.deviceKey });
    expect(res.status).toBe(204);
    expect((await call("POST", "/invites", { deviceKey: owner.deviceKey })).status).toBe(401);
  });

  it("does not let one member remove another", async () => {
    const owner = await createFamily();
    const mother = await joinAs(owner, "protected", "母");
    const res = await call("DELETE", `/members/${mother.memberId}`, { deviceKey: owner.deviceKey });
    expect(res.status).toBe(403);
    expect((await call("POST", "/invites", { deviceKey: mother.deviceKey })).status).toBe(201);
  });
});

describe("DELETE /families/me (delete everything)", () => {
  it("removes the family's rows from every table, its photos, the Gmail grant, and its agent sessions", async () => {
    const family = await createFamily("作者");
    const mother = await joinAs(family, "protected", "母");
    await invite(family.deviceKey); // an unused invite stays in the table until deleted
    await seed(family, { sessionId: "sesn_family_a", refreshToken: "refresh-token-a" });
    await seed(family, { sessionId: "sesn_family_b" });

    const other = await createFamily("別の家族");
    await seed(other, { sessionId: "sesn_other", refreshToken: "refresh-token-other" });

    const revoked: string[] = [];
    const deletedSessions: string[] = [];
    network.use(
      http.post("https://oauth2.googleapis.com/revoke", async ({ request }) => {
        expect(request.headers.get("content-type")).toContain("application/x-www-form-urlencoded");
        revoked.push(new URLSearchParams(await request.text()).get("token") ?? "");
        return new HttpResponse(null, { status: 200 });
      }),
      http.delete("https://api.anthropic.com/v1/sessions/:id", ({ request, params }) => {
        expect(request.headers.get("x-api-key")).toBe(env.ANTHROPIC_API_KEY);
        expect(request.headers.get("anthropic-version")).toBe("2023-06-01");
        expect(request.headers.get("anthropic-beta")).toBe("managed-agents-2026-04-01");
        deletedSessions.push(String(params.id));
        return HttpResponse.json({ id: params.id, type: "session_deleted" });
      }),
    );

    const res = await call("DELETE", "/families/me", { deviceKey: mother.deviceKey });
    expect(res.status).toBe(204);

    expect(revoked).toEqual(["refresh-token-a"]);
    expect(deletedSessions.sort()).toEqual(["sesn_family_a", "sesn_family_b"]);
    expect(await countFor(family.familyId)).toEqual({
      members: 0,
      invites: 0,
      alerts: 0,
      cases: 0,
      smiles: 0,
      gmail_auth: 0,
      relays: 0,
      families: 0,
    });
    expect(await r2Count(`${family.familyId}/`)).toBe(0);
    expect((await call("POST", "/invites", { deviceKey: family.deviceKey })).status).toBe(401);

    // The other family is untouched.
    const kept = await countFor(other.familyId);
    expect(kept).toMatchObject({ members: 1, alerts: 1, cases: 1, smiles: 1, gmail_auth: 1, relays: 1, families: 1 });
    expect(await r2Count(`${other.familyId}/`)).toBe(1);
  });

  it("treats an already revoked grant and an already deleted session as done", async () => {
    const family = await createFamily();
    await seed(family, { sessionId: "sesn_gone", refreshToken: "already-revoked" });
    network.use(
      http.post("https://oauth2.googleapis.com/revoke", () =>
        HttpResponse.json({ error: "invalid_token" }, { status: 400 }),
      ),
      http.delete("https://api.anthropic.com/v1/sessions/:id", () =>
        HttpResponse.json({ type: "error", error: { type: "not_found_error" } }, { status: 404 }),
      ),
    );

    const res = await call("DELETE", "/families/me", { deviceKey: family.deviceKey });
    expect(res.status).toBe(204);
    expect((await countFor(family.familyId)).families).toBe(0);
  });

  it("keeps the data and answers 502 when a session cannot be deleted, so the request can be retried", async () => {
    const family = await createFamily();
    await seed(family, { sessionId: "sesn_stuck", refreshToken: "token" });
    network.use(
      http.post("https://oauth2.googleapis.com/revoke", () => new HttpResponse(null, { status: 200 })),
      http.delete("https://api.anthropic.com/v1/sessions/:id", () =>
        HttpResponse.json({ type: "error", error: { type: "api_error" } }, { status: 500 }),
      ),
    );

    const res = await call("DELETE", "/families/me", { deviceKey: family.deviceKey });
    expect(res.status).toBe(502);
    expect(await res.json()).toEqual({ error: "cleanup_failed", pending: ["agent_sessions"] });
    expect((await countFor(family.familyId)).families).toBe(1);
    expect((await call("POST", "/invites", { deviceKey: family.deviceKey })).status).toBe(201);
  });
});

describe("DELETE /families/me when outside services fail", () => {
  it("answers 502 with gmail pending when Google does not revoke the grant", async () => {
    const family = await createFamily();
    await seed(family, { refreshToken: "token" });
    network.use(
      http.post("https://oauth2.googleapis.com/revoke", () => HttpResponse.json({ error: "server_error" }, { status: 500 })),
    );

    const res = await call("DELETE", "/families/me", { deviceKey: family.deviceKey });
    expect(res.status).toBe(502);
    expect(await res.json()).toEqual({ error: "cleanup_failed", pending: ["gmail"] });
    expect((await countFor(family.familyId)).families).toBe(1);
  });

  it("answers 502, not 500, when the request to Anthropic itself throws", async () => {
    const family = await createFamily();
    await seed(family, { sessionId: "sesn_network_down" });
    network.use(http.delete("https://api.anthropic.com/v1/sessions/:id", () => HttpResponse.error()));

    const res = await call("DELETE", "/families/me", { deviceKey: family.deviceKey });
    expect(res.status).toBe(502);
    expect(await res.json()).toEqual({ error: "cleanup_failed", pending: ["agent_sessions"] });
  });

  it("stays within 40 outside calls per request and finishes on the next call", async () => {
    const family = await createFamily();
    await seed(family, { refreshToken: "token" });
    const sessions = await seedSessions(family, 45, Date.now());
    let calls = 0;
    const deleted: string[] = [];
    network.use(
      http.post("https://oauth2.googleapis.com/revoke", () => {
        calls++;
        return new HttpResponse(null, { status: 200 });
      }),
      http.delete("https://api.anthropic.com/v1/sessions/:id", ({ params }) => {
        calls++;
        deleted.push(String(params.id));
        return HttpResponse.json({ id: params.id, type: "session_deleted" });
      }),
    );

    const first = await call("DELETE", "/families/me", { deviceKey: family.deviceKey });
    expect(first.status).toBe(502);
    expect(await first.json()).toEqual({ error: "cleanup_failed", pending: ["agent_sessions"] });
    expect(calls).toBeLessThanOrEqual(40);

    calls = 0;
    const second = await call("DELETE", "/families/me", { deviceKey: family.deviceKey });
    expect(second.status).toBe(204);
    expect(calls).toBeLessThanOrEqual(40);
    expect(deleted.sort()).toEqual([...sessions].sort());
    expect((await countFor(family.familyId)).families).toBe(0);
  });
});

describe("cron", () => {
  // 04:00 JST is 19:00 UTC on the previous day.
  const cleanupTick = Date.UTC(2026, 10, 5, 19, 0, 0);

  it("runs the cleanup once a day at 04:00 JST and nothing else from the daily list at other ticks", () => {
    expect(dueJobs(cleanupTick, JOBS).map((j) => j.name)).toContain("retention");
    expect(dueJobs(cleanupTick + 5 * 60_000, JOBS).map((j) => j.name)).not.toContain("retention");
    expect(dueJobs(cleanupTick - 5 * 60_000, JOBS).map((j) => j.name)).not.toContain("retention");
  });

  it("runs every-5-minute jobs at each tick", () => {
    const jobs = [
      { name: "watch", everyMinutes: 5, run: async () => {} },
      { name: "daily", dailyAtJst: "04:00", run: async () => {} },
    ];
    expect(dueJobs(cleanupTick + 5 * 60_000, jobs).map((j) => j.name)).toEqual(["watch"]);
    expect(dueJobs(cleanupTick, jobs).map((j) => j.name)).toEqual(["watch", "daily"]);
  });

  it("deletes alerts, cases, relays, and smiles older than 30 days, photos included", async () => {
    const family = await createFamily();
    const old = await seed(family, { at: cleanupTick - 31 * DAY });
    const recent = await seed(family, { at: cleanupTick - 29 * DAY });

    const ctx = createExecutionContext();
    await worker.scheduled(
      createScheduledController({ scheduledTime: cleanupTick, cron: "*/5 * * * *" }),
      env,
      ctx,
    );
    await waitOnExecutionContext(ctx);

    const ids = async (table: string) =>
      (
        await env.DB.prepare(`SELECT id FROM ${table} WHERE family_id = ?`).bind(family.familyId).all<{ id: string }>()
      ).results.map((r) => r.id);
    expect(await ids("alerts")).toEqual([recent.alertId]);
    expect(await ids("cases")).toEqual([recent.caseId]);
    expect(await ids("smiles")).toEqual([recent.smileId]);
    const relays = await env.DB.prepare("SELECT case_id FROM relays WHERE case_id IN (?, ?)")
      .bind(old.caseId, recent.caseId)
      .all<{ case_id: string }>();
    expect(relays.results.map((r) => r.case_id)).toEqual([recent.caseId]);
    expect(await env.PHOTOS.head(old.r2Key)).toBeNull();
    expect(await env.PHOTOS.head(recent.r2Key)).not.toBeNull();
    // The family and its members are not time-limited.
    expect((await countFor(family.familyId)).members).toBe(1);
  });

  it("deletes the agent session of an old case, and keeps the case when the session cannot be deleted yet", async () => {
    const family = await createFamily();
    const gone = await seed(family, { at: cleanupTick - 31 * DAY, sessionId: "sesn_old_done" });
    const stuck = await seed(family, { at: cleanupTick - 31 * DAY, sessionId: "sesn_old_running" });
    const deleted: string[] = [];
    network.use(
      http.delete("https://api.anthropic.com/v1/sessions/:id", ({ params }) => {
        if (params.id === "sesn_old_running") {
          return HttpResponse.json({ type: "error", error: { type: "invalid_request_error" } }, { status: 400 });
        }
        deleted.push(String(params.id));
        return HttpResponse.json({ id: params.id, type: "session_deleted" });
      }),
    );

    const ctx = createExecutionContext();
    await worker.scheduled(
      createScheduledController({ scheduledTime: cleanupTick, cron: "*/5 * * * *" }),
      env,
      ctx,
    );
    await waitOnExecutionContext(ctx);

    expect(deleted).toEqual(["sesn_old_done"]);
    const cases = await env.DB.prepare("SELECT id FROM cases WHERE family_id = ?").bind(family.familyId).all<{ id: string }>();
    expect(cases.results.map((r) => r.id)).toEqual([stuck.caseId]);
    expect(cases.results.map((r) => r.id)).not.toContain(gone.caseId);
  });

  it("deletes 60 due sessions over several ticks, at most 40 outside calls per run", async () => {
    // Storage is shared within this file; start without old cases left by earlier tests.
    await env.DB.prepare("DELETE FROM cases").run();
    const family = await createFamily();
    const sessions = await seedSessions(family, 60, cleanupTick - 31 * DAY);
    const perRun: number[] = [];
    const deleted: string[] = [];
    network.use(
      http.delete("https://api.anthropic.com/v1/sessions/:id", ({ params }) => {
        perRun[perRun.length - 1] = (perRun.at(-1) ?? 0) + 1;
        deleted.push(String(params.id));
        return HttpResponse.json({ id: params.id, type: "session_deleted" });
      }),
    );

    for (const offset of [0, 5, 10]) {
      perRun.push(0);
      await tick(cleanupTick + offset * 60_000);
    }
    expect(perRun.every((n) => n <= 40)).toBe(true);
    expect(deleted.sort()).toEqual([...sessions].sort());
    const left = await env.DB.prepare("SELECT COUNT(*) AS n FROM cases WHERE family_id = ?")
      .bind(family.familyId)
      .first<{ n: number }>();
    expect(left?.n).toBe(0);
    // Nothing left to do: later ticks make no outside calls.
    perRun.push(0);
    await tick(cleanupTick + 15 * 60_000);
    expect(perRun.at(-1)).toBe(0);
  });

  it("still deletes old alerts, smiles, and photos when a session delete throws", async () => {
    const family = await createFamily();
    const old = await seed(family, { at: cleanupTick - 31 * DAY, sessionId: "sesn_throws" });
    network.use(http.delete("https://api.anthropic.com/v1/sessions/:id", () => HttpResponse.error()));

    await tick(cleanupTick);

    const counts = await countFor(family.familyId);
    expect(counts.alerts).toBe(0);
    expect(counts.smiles).toBe(0);
    expect(await env.PHOTOS.head(old.r2Key)).toBeNull();
    // The case waits for its session to be deleted on a later tick.
    expect(counts.cases).toBe(1);
  });

  it("leaves data alone at ticks where the cleanup is not due", async () => {
    const family = await createFamily();
    await seed(family, { at: cleanupTick - 40 * DAY });

    const ctx = createExecutionContext();
    await worker.scheduled(
      createScheduledController({ scheduledTime: cleanupTick + 5 * 60_000, cron: "*/5 * * * *" }),
      env,
      ctx,
    );
    await waitOnExecutionContext(ctx);
    expect((await countFor(family.familyId)).alerts).toBe(1);
  });
});
