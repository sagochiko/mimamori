// Task 10 "家族への知らせと解決" in docs/plan.md: opening a case, "解決" by any family member, the
// accept and relay routes being gone, and the 30-minute watch.

import { createExecutionContext, createScheduledController, waitOnExecutionContext } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { http, HttpResponse } from "msw";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import { ExternalBudget } from "../src/budget";
import {
  NO_REPLY_YET,
  NOT_RESOLVED_YET,
  openCase,
  recordAiReply,
  resolveCase,
  UNANSWERED_AFTER_MS,
} from "../src/cases";
import { JOBS } from "../src/cron";
import worker from "../src/index";
import { resetApnsJwtCache } from "../src/push";
import { call, createFamily, invite, join } from "./helpers";
import { network } from "./network";

const SANDBOX = "https://api.sandbox.push.apple.com";
let pushEnv: Env;

beforeAll(async () => {
  // A throwaway P-256 key stands in for the .p8 from Apple.
  const pair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign"])) as CryptoKeyPair;
  const der = (await crypto.subtle.exportKey("pkcs8", pair.privateKey)) as ArrayBuffer;
  const b64 = btoa(String.fromCharCode(...new Uint8Array(der)));
  pushEnv = { ...env, APNS_KEY_P8: `-----BEGIN PRIVATE KEY-----\n${b64}\n-----END PRIVATE KEY-----` };
});

interface Sent {
  token: string;
  title?: string;
  body: string;
  data: Record<string, unknown>;
}
let sent: Sent[];

beforeEach(() => {
  resetApnsJwtCache();
  sent = [];
  network.use(
    http.post(`${SANDBOX}/3/device/:token`, async ({ request, params }) => {
      const payload = (await request.json()) as { aps: { alert: { title?: string; body: string } } } & Record<string, unknown>;
      const { aps, ...data } = payload;
      sent.push({ token: String(params.token), title: aps.alert.title, body: aps.alert.body, data });
      return new HttpResponse(null, { status: 200 });
    }),
  );
});

interface Person {
  memberId: string;
  deviceKey: string;
  token: string;
}

/** The author and the sister (family) and the mother (protected), each with an APNs token. */
async function family() {
  const author = await createFamily("作者");
  const joinAs = async (role: "protected" | "family", name: string) => {
    const { code } = await invite(author.deviceKey);
    return (await (await join(code, role, name)).json()) as { memberId: string; deviceKey: string };
  };
  const sister = await joinAs("family", "妹");
  const mother = await joinAs("protected", "母");
  const people: Record<"author" | "sister" | "mother", Person> = {
    author: { memberId: author.memberId, deviceKey: author.deviceKey, token: hexToken() },
    sister: { ...sister, token: hexToken() },
    mother: { ...mother, token: hexToken() },
  };
  for (const p of Object.values(people)) {
    await env.DB.prepare("UPDATE members SET apns_token = ?, apns_env = 'sandbox' WHERE id = ?")
      .bind(p.token, p.memberId)
      .run();
  }
  return { familyId: author.familyId, ...people };
}

function hexToken(): string {
  return [...crypto.getRandomValues(new Uint8Array(32))].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function newAlert(familyId: string, opts: { level?: 1 | 2 | 3; summary?: string } = {}): Promise<string> {
  const id = crypto.randomUUID();
  await env.DB.prepare(
    "INSERT INTO alerts (id, family_id, source, level, reasons, summary, created_at) VALUES (?, ?, 'call', ?, ?, ?, ?)",
  )
    .bind(id, familyId, opts.level ?? 1, JSON.stringify(["警察を名乗り、口座の移し替えを求めた"]), opts.summary ?? "警察を名乗る電話の相談", Date.now())
    .run();
  return id;
}

async function caseRow(caseId: string) {
  return env.DB.prepare(
    "SELECT state, assignee_member_id, accepted_at, resolved_at, renotified_at, ai_reply FROM cases WHERE id = ?",
  )
    .bind(caseId)
    .first<{
      state: string;
      assignee_member_id: string | null;
      accepted_at: number | null;
      resolved_at: number | null;
      renotified_at: number | null;
      ai_reply: string | null;
    }>();
}

async function tick(scheduledTime: number): Promise<void> {
  const ctx = createExecutionContext();
  await worker.scheduled(createScheduledController({ scheduledTime, cron: "*/5 * * * *" }), pushEnv, ctx);
  await waitOnExecutionContext(ctx);
}

async function backdate(caseId: string, minutes: number): Promise<number> {
  const at = Date.now() - minutes * 60_000;
  await env.DB.prepare("UPDATE cases SET notified_at = ? WHERE id = ?").bind(at, caseId).run();
  return at;
}

function to(p: Person): Sent[] {
  return sent.filter((s) => s.token === p.token);
}

/** openCase with a fresh 40-call budget, as one queue message would have. */
function open(alertId: string, budget = new ExternalBudget()) {
  return openCase(pushEnv, alertId, budget);
}

async function caseOf(alertId: string) {
  return env.DB.prepare("SELECT id, state, family_notified_at FROM cases WHERE alert_id = ?")
    .bind(alertId)
    .first<{ id: string; state: string; family_notified_at: number | null }>();
}

async function casesFor(alertId: string): Promise<number> {
  const row = await env.DB.prepare("SELECT COUNT(*) AS n FROM cases WHERE alert_id = ?").bind(alertId).first<{ n: number }>();
  return row?.n ?? 0;
}

/** APNs answers 500 for these devices until `ok` is set. */
function apnsFailsFor(tokens: string[]): { ok: boolean } {
  const state = { ok: false };
  network.use(
    http.post(`${SANDBOX}/3/device/:token`, ({ params }) => {
      if (state.ok || !tokens.includes(String(params.token))) return undefined;
      return HttpResponse.json({ reason: "InternalServerError" }, { status: 500 });
    }),
  );
  return state;
}

describe("openCase", () => {
  it("records a notified case and tells every family member, not the protected person", async () => {
    const f = await family();
    const alertId = await newAlert(f.familyId, { summary: "警察を名乗る電話の相談" });

    const opened = await open(alertId);

    expect(opened?.state).toBe("notified");
    expect((await caseRow(opened?.id ?? ""))?.state).toBe("notified");
    expect(to(f.author)).toHaveLength(1);
    expect(to(f.sister)).toHaveLength(1);
    expect(to(f.mother)).toHaveLength(0);
    expect(to(f.author)[0]?.body).toContain("警察を名乗る電話の相談");
    expect(to(f.author)[0]?.data.caseId).toBe(opened?.id);
  });

  it("opens one case per alert even when called twice (a retried queue message)", async () => {
    const f = await family();
    const alertId = await newAlert(f.familyId);

    const [a, b] = await Promise.all([open(alertId), open(alertId)]);

    expect(a?.id).toBe(b?.id);
    const n = await env.DB.prepare("SELECT COUNT(*) AS n FROM cases WHERE alert_id = ?").bind(alertId).first<{ n: number }>();
    expect(n?.n).toBe(1);
    // Family members are told once, not twice.
    expect(to(f.author)).toHaveLength(1);
  });

  it("returns null for an alert that does not exist", async () => {
    expect(await open("no-such-alert")).toBeNull();
  });

  it("takes one ticket per family device from the caller's shared budget", async () => {
    const f = await family();
    const budget = new ExternalBudget(40);

    await open(await newAlert(f.familyId), budget);

    expect(budget.remaining).toBe(38);
  });

  it("when the budget cannot cover the family, keeps the case untold and throws, and the retry tells the family", async () => {
    const f = await family();
    const alertId = await newAlert(f.familyId);

    await expect(open(alertId, new ExternalBudget(1))).rejects.toMatchObject({ name: "CaseNoticeDeferred" });
    const kept = await caseOf(alertId);
    expect(kept).toMatchObject({ state: "notified", family_notified_at: null });
    expect(sent).toHaveLength(0);

    const opened = await open(alertId);
    expect(opened?.id).toBe(kept?.id);
    expect(to(f.author)).toHaveLength(1);
    expect(to(f.sister)).toHaveLength(1);
    expect((await caseOf(alertId))?.family_notified_at).not.toBeNull();
  });

  it("when no family device took the notice, keeps the case untold and throws, and the retry tells the family", async () => {
    const f = await family();
    const alertId = await newAlert(f.familyId);
    const apns = apnsFailsFor([f.author.token, f.sister.token]);

    await expect(open(alertId)).rejects.toMatchObject({ name: "CaseNoticeDeferred" });
    const kept = await caseOf(alertId);
    expect(kept).toMatchObject({ state: "notified", family_notified_at: null });
    // The protected person's screen and the family's list still see it.
    const list = await call("GET", "/cases", { deviceKey: f.mother.deviceKey, env: pushEnv });
    expect(((await list.json()) as { cases: Array<{ id: string }> }).cases.map((c) => c.id)).toContain(kept?.id);

    apns.ok = true;
    const opened = await open(alertId);
    expect(opened?.id).toBe(kept?.id);
    expect(await casesFor(alertId)).toBe(1);
    expect(to(f.author)).toHaveLength(1);
    expect(to(f.sister)).toHaveLength(1);
    expect(to(f.author)[0]?.data.caseId).toBe(kept?.id);
  });

  it("an AI answer recorded while the family was still untold survives the retry", async () => {
    const f = await family();
    const alertId = await newAlert(f.familyId);
    const apns = apnsFailsFor([f.author.token, f.sister.token]);
    await expect(open(alertId)).rejects.toMatchObject({ name: "CaseNoticeDeferred" });
    const caseId = (await caseOf(alertId))?.id ?? "";

    await recordAiReply(pushEnv, caseId, "送金せず、家族に確かめて");
    apns.ok = true;
    const opened = await open(alertId);

    expect(opened?.aiReply).toBe("送金せず、家族に確かめて");
  });

  it("once the family was told, a second call neither tells them again nor takes tickets", async () => {
    const f = await family();
    const alertId = await newAlert(f.familyId);
    await open(alertId);
    sent = [];
    const budget = new ExternalBudget(40);

    await open(alertId, budget);

    expect(sent).toHaveLength(0);
    expect(budget.remaining).toBe(40);
  });

  it("keeps the case when at least one family member was told; the 30-minute watch covers the rest", async () => {
    const f = await family();
    const alertId = await newAlert(f.familyId);
    apnsFailsFor([f.sister.token]);

    const opened = await open(alertId);

    expect(opened?.state).toBe("notified");
    expect(to(f.author)).toHaveLength(1);
  });

  it("opens the case without throwing when no family member has a device to notify", async () => {
    const f = await family();
    await env.DB.prepare("UPDATE members SET apns_token = NULL WHERE family_id = ? AND role = 'family'")
      .bind(f.familyId)
      .run();

    const opened = await open(await newAlert(f.familyId), new ExternalBudget(0));

    expect(opened?.state).toBe("notified");
    // Nobody to tell is not "untold": the 5-minute tick does not keep retrying it.
    expect((await caseOf(opened?.alertId ?? ""))?.family_notified_at).not.toBeNull();
  });
});

describe("taking a case over and replying are gone", () => {
  it("POST /cases/{id}/accept and /relay answer 404 and change nothing", async () => {
    const f = await family();
    const caseId = (await open(await newAlert(f.familyId)))?.id ?? "";
    sent = [];

    for (const verb of ["accept", "relay"]) {
      for (const p of [f.author, f.sister, f.mother]) {
        const res = await call("POST", `/cases/${caseId}/${verb}`, {
          deviceKey: p.deviceKey,
          body: { body: "今から電話するね" },
          env: pushEnv,
        });
        expect(res.status).toBe(404);
      }
    }

    expect(await caseRow(caseId)).toMatchObject({ state: "notified", assignee_member_id: null, accepted_at: null });
    const relays = await env.DB.prepare("SELECT COUNT(*) AS n FROM relays WHERE case_id = ?").bind(caseId).first<{ n: number }>();
    expect(relays?.n).toBe(0);
    expect(sent).toHaveLength(0);
  });
});

describe("the AI's answer on the card", () => {
  it("the latest answer the AI gave is always kept and the family card shows it", async () => {
    const f = await family();
    const caseId = (await open(await newAlert(f.familyId)))?.id ?? "";

    await recordAiReply(env, caseId, "送金はせず、いったん電話を切って");
    await recordAiReply(env, caseId, "お金や暗証番号の話には応じず、家族に確かめて");

    const list = await call("GET", "/cases", { deviceKey: f.author.deviceKey, env: pushEnv });
    const view = ((await list.json()) as { cases: Array<{ id: string; aiReply: string | null }> }).cases.find(
      (c) => c.id === caseId,
    );
    expect(view?.aiReply).toBe("お金や暗証番号の話には応じず、家族に確かめて");
  });
});

describe("resolve", () => {
  it("any family member resolves, and the rest of the family hears '(名前)が解決'", async () => {
    const f = await family();
    const caseId = (await open(await newAlert(f.familyId)))?.id ?? "";
    sent = [];

    const res = await call("POST", `/cases/${caseId}/resolve`, { deviceKey: f.sister.deviceKey, env: pushEnv });
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({
      state: "resolved",
      resolvedBy: { memberId: f.sister.memberId, displayName: "妹" },
    });
    expect((await caseRow(caseId))?.resolved_at).not.toBeNull();

    expect(to(f.author).map((s) => s.body)).toEqual(["妹が解決"]);
    expect(to(f.author)[0]?.data.caseId).toBe(caseId);
    // Not the one who pressed it, and not the protected person: her card for the case goes away.
    expect(to(f.sister)).toHaveLength(0);
    expect(to(f.mother)).toHaveLength(0);
  });

  it("of two near-simultaneous presses, one records it and the family is told once", async () => {
    const f = await family();
    const caseId = (await open(await newAlert(f.familyId)))?.id ?? "";
    sent = [];

    const [a, s] = await Promise.all([
      call("POST", `/cases/${caseId}/resolve`, { deviceKey: f.author.deviceKey, env: pushEnv }),
      call("POST", `/cases/${caseId}/resolve`, { deviceKey: f.sister.deviceKey, env: pushEnv }),
    ]);
    expect([a.status, s.status]).toEqual([200, 200]);
    const views = [(await a.json()) as { resolvedBy: { memberId: string } }, (await s.json()) as { resolvedBy: { memberId: string } }];
    const winner = (await caseRow(caseId))?.assignee_member_id;
    expect(views.map((v) => v.resolvedBy.memberId)).toEqual([winner, winner]);
    // Only the other of the two hears it.
    expect(sent).toHaveLength(1);
    expect(sent[0]?.token).toBe(winner === f.author.memberId ? f.sister.token : f.author.token);
  });

  it("pressing it again later is not an error and tells nobody again", async () => {
    const f = await family();
    const caseId = (await open(await newAlert(f.familyId)))?.id ?? "";
    await resolveCase(pushEnv, caseId, f.sister.memberId);
    sent = [];

    const again = await call("POST", `/cases/${caseId}/resolve`, { deviceKey: f.author.deviceKey, env: pushEnv });
    expect(again.status).toBe(200);
    expect(((await again.json()) as { resolvedBy: { displayName: string } }).resolvedBy.displayName).toBe("妹");
    expect(sent).toHaveLength(0);
  });

  it("the protected person cannot resolve, and another family cannot see the case", async () => {
    const f = await family();
    const other = await createFamily("別の家族");
    const caseId = (await open(await newAlert(f.familyId)))?.id ?? "";

    const byMother = await call("POST", `/cases/${caseId}/resolve`, { deviceKey: f.mother.deviceKey, env: pushEnv });
    expect(byMother.status).toBe(403);
    const byStranger = await call("POST", `/cases/${caseId}/resolve`, { deviceKey: other.deviceKey, env: pushEnv });
    expect(byStranger.status).toBe(404);
    expect((await caseRow(caseId))?.state).toBe("notified");
  });

  it("a case resolved by someone who then left stays resolved, named 家族", async () => {
    const f = await family();
    const caseId = (await open(await newAlert(f.familyId)))?.id ?? "";
    await resolveCase(pushEnv, caseId, f.sister.memberId);

    await call("DELETE", "/members/me", { deviceKey: f.sister.deviceKey, env: pushEnv });

    const list = await call("GET", "/cases", { deviceKey: f.author.deviceKey, env: pushEnv });
    const view = ((await list.json()) as { cases: Array<Record<string, unknown>> }).cases.find((c) => c.id === caseId);
    expect(view).toMatchObject({ state: "resolved", resolvedBy: { memberId: f.sister.memberId, displayName: "家族" } });
  });

  it("a case left in the old 'accepted' state is shown as not resolved and can be resolved", async () => {
    const f = await family();
    const caseId = (await open(await newAlert(f.familyId)))?.id ?? "";
    await env.DB.prepare("UPDATE cases SET state = 'accepted', assignee_member_id = ?, accepted_at = ? WHERE id = ?")
      .bind(f.sister.memberId, Date.now(), caseId)
      .run();

    const list = await call("GET", "/cases", { deviceKey: f.author.deviceKey, env: pushEnv });
    const view = ((await list.json()) as { cases: Array<Record<string, unknown>> }).cases.find((c) => c.id === caseId);
    expect(view).toMatchObject({ state: "notified", resolvedBy: null });

    const done = await resolveCase(pushEnv, caseId, f.author.memberId);
    expect(done).toMatchObject({ state: "resolved", resolvedBy: { memberId: f.author.memberId, displayName: "作者" } });
  });
});

describe("GET /cases", () => {
  it("lists the family's cases with the alert and the AI's answer, and nothing from other families", async () => {
    const f = await family();
    const other = await family();
    const mine = (await open(await newAlert(f.familyId, { level: 2, summary: "SMS 宅配の不在の知らせをかたっている" })))?.id ?? "";
    const theirs = (await open(await newAlert(other.familyId)))?.id ?? "";

    const res = await call("GET", "/cases", { deviceKey: f.author.deviceKey, env: pushEnv });
    expect(res.status).toBe(200);
    const { cases } = (await res.json()) as { cases: Array<Record<string, unknown>> };
    expect(cases.map((c) => c.id)).toEqual([mine]);
    expect(cases.map((c) => c.id)).not.toContain(theirs);
    expect(cases[0]).toMatchObject({
      state: "notified",
      resolvedBy: null,
      resolvedAt: null,
      alert: {
        level: 2,
        source: "call",
        summary: "SMS 宅配の不在の知らせをかたっている",
        reasons: ["警察を名乗り、口座の移し替えを求めた"],
      },
      aiReply: null,
    });
    // Nothing of the hand-off is left in the shape.
    for (const gone of ["assignee", "assigneeMemberId", "acceptedAt", "relays"]) expect(cases[0]).not.toHaveProperty(gone);
    expect(typeof cases[0]?.notifiedAt).toBe("string");
  });

  it("needs a device key", async () => {
    expect((await call("GET", "/cases")).status).toBe(401);
  });
});

describe("the 30-minute watch", () => {
  beforeEach(async () => {
    // Storage is shared within this file; old cases from earlier tests would be picked up too.
    await env.DB.prepare("DELETE FROM cases").run();
  });

  it("runs in the 5-minute dispatcher, before the session cleanup", () => {
    const names = JOBS.filter((j) => "everyMinutes" in j && j.everyMinutes === 5).map((j) => j.name);
    expect(names.indexOf("case-watch")).toBeGreaterThanOrEqual(0);
    expect(names.indexOf("case-watch")).toBeLessThan(names.indexOf("retention-sessions"));
  });

  it("after 30 minutes without '解決', tells the protected person and notifies the family again, once", async () => {
    const f = await family();
    const caseId = (await open(await newAlert(f.familyId)))?.id ?? "";
    await backdate(caseId, 31);
    sent = [];

    await tick(Date.now());

    expect(to(f.mother).map((s) => s.body)).toEqual([NO_REPLY_YET]);
    expect(NO_REPLY_YET).toBe("家族から返事がまだ。急ぐなら電話して");
    expect(to(f.author)).toEqual([expect.objectContaining({ title: "まだ解決していません", body: "警察を名乗る電話の相談" })]);
    expect(to(f.sister)).toEqual([expect.objectContaining({ title: NOT_RESOLVED_YET })]);
    expect((await caseRow(caseId))?.renotified_at).not.toBeNull();

    // Later ticks do not notify again.
    sent = [];
    await tick(Date.now() + 5 * 60_000);
    await tick(Date.now() + 10 * 60_000);
    expect(sent).toHaveLength(0);
  });

  it("while nobody has responded, nothing tells the protected person it is solved or being handled", async () => {
    const f = await family();
    const caseId = (await open(await newAlert(f.familyId)))?.id ?? "";
    await backdate(caseId, 45);
    sent = [];

    await tick(Date.now());

    const row = await caseRow(caseId);
    expect(row?.state).toBe("notified");
    expect(row?.assignee_member_id).toBeNull();
    for (const s of to(f.mother)) {
      expect(`${s.title ?? ""}${s.body}`).not.toMatch(/解決|対応中|見ています|安全/);
    }
    const list = await call("GET", "/cases", { deviceKey: f.mother.deviceKey, env: pushEnv });
    const view = ((await list.json()) as { cases: Array<Record<string, unknown>> }).cases.find((c) => c.id === caseId);
    expect(view).toMatchObject({ state: "notified", resolvedBy: null, resolvedAt: null });
    expect(typeof view?.renotifiedAt).toBe("string");
  });

  it("leaves alone a case resolved in time, and one that is not yet 30 minutes old", async () => {
    const f = await family();
    const resolved = (await open(await newAlert(f.familyId)))?.id ?? "";
    await resolveCase(pushEnv, resolved, f.author.memberId);
    await backdate(resolved, 40);
    const young = (await open(await newAlert(f.familyId)))?.id ?? "";
    await backdate(young, 29);
    sent = [];

    await tick(Date.now());

    expect(sent).toHaveLength(0);
    expect((await caseRow(young))?.renotified_at).toBeNull();
    expect(UNANSWERED_AFTER_MS).toBe(30 * 60_000);
  });

  it("shares the 40-call budget with the session cleanup, and the notices go first", async () => {
    const f = await family();
    const caseId = (await open(await newAlert(f.familyId)))?.id ?? "";
    await backdate(caseId, 31);
    // 45 old cases waiting for their agent sessions to be deleted.
    const old = Date.now() - 31 * 24 * 3600_000;
    await env.DB.batch(
      Array.from({ length: 45 }, (_, i) =>
        env.DB.prepare(
          "INSERT INTO cases (id, family_id, state, agent_session_id, notified_at) VALUES (?, ?, 'resolved', ?, ?)",
        ).bind(crypto.randomUUID(), f.familyId, `sesn_watch_${i}`, old),
      ),
    );
    let deletes = 0;
    network.use(
      http.delete("https://api.anthropic.com/v1/sessions/:id", ({ params }) => {
        deletes++;
        return HttpResponse.json({ id: params.id, type: "session_deleted" });
      }),
    );
    sent = [];

    await tick(Date.now());

    // Three devices (mother, author, sister) were told; the cleanup used what was left.
    expect(sent).toHaveLength(3);
    expect(sent.length + deletes).toBeLessThanOrEqual(40);
    expect(deletes).toBe(37);
  });

  it("watches a case left in the old 'accepted' state like any case that is not resolved", async () => {
    const f = await family();
    const caseId = (await open(await newAlert(f.familyId)))?.id ?? "";
    await env.DB.prepare("UPDATE cases SET state = 'accepted', assignee_member_id = ?, accepted_at = ? WHERE id = ?")
      .bind(f.sister.memberId, Date.now(), caseId)
      .run();
    await backdate(caseId, 31);
    sent = [];

    await tick(Date.now());

    expect(to(f.mother).map((s) => s.body)).toEqual([NO_REPLY_YET]);
    expect(to(f.author)).toHaveLength(1);
    expect(to(f.sister)).toHaveLength(1);
  });

  it("tells the family about a case the queue gave up on, at the next tick, once", async () => {
    const f = await family();
    const alertId = await newAlert(f.familyId, { level: 1, summary: "警察を名乗る電話の相談" });
    const apns = apnsFailsFor([f.author.token, f.sister.token]);
    // The queue's three tries all fail, then it stops retrying the message.
    for (let i = 0; i < 3; i++) {
      await expect(open(alertId)).rejects.toMatchObject({ name: "CaseNoticeDeferred" });
    }
    apns.ok = true;
    sent = [];

    await tick(Date.now());

    expect(to(f.author)).toHaveLength(1);
    expect(to(f.sister)).toHaveLength(1);
    expect(to(f.mother)).toHaveLength(0);
    expect(to(f.author)[0]).toMatchObject({ title: "1段階", body: "警察を名乗る電話の相談" });
    expect(to(f.author)[0]?.data.caseId).toBe((await caseOf(alertId))?.id);
    sent = [];
    await tick(Date.now() + 5 * 60_000);
    expect(sent).toHaveLength(0);
  });

  it("an untold case is still watched: after 30 minutes the protected person hears, even while the family's devices fail", async () => {
    const f = await family();
    const alertId = await newAlert(f.familyId);
    apnsFailsFor([f.author.token, f.sister.token]);
    await expect(open(alertId)).rejects.toMatchObject({ name: "CaseNoticeDeferred" });
    await backdate((await caseOf(alertId))?.id ?? "", 31);
    sent = [];

    await tick(Date.now());

    expect(to(f.mother).map((s) => s.body)).toEqual([NO_REPLY_YET]);
  });

  it("does not remind about a case older than a day", async () => {
    const f = await family();
    const caseId = (await open(await newAlert(f.familyId)))?.id ?? "";
    await backdate(caseId, 25 * 60);
    sent = [];

    await tick(Date.now());

    expect(sent).toHaveLength(0);
    expect((await caseRow(caseId))?.renotified_at).toBeNull();
  });

  it("stops retrying a first notice after a day", async () => {
    const f = await family();
    const alertId = await newAlert(f.familyId);
    const apns = apnsFailsFor([f.author.token, f.sister.token]);
    await expect(open(alertId)).rejects.toMatchObject({ name: "CaseNoticeDeferred" });
    const caseId = (await caseOf(alertId))?.id ?? "";
    // Already reminded by the watch, so only the first notice is left.
    await env.DB.prepare("UPDATE cases SET notified_at = ?, renotified_at = ? WHERE id = ?")
      .bind(Date.now() - 25 * 3600_000, Date.now() - 24 * 3600_000, caseId)
      .run();
    apns.ok = true;
    sent = [];

    await tick(Date.now());

    expect(sent).toHaveLength(0);
  });

  it("runs the first-notice retry before the 30-minute watch", () => {
    const names = JOBS.filter((j) => "everyMinutes" in j && j.everyMinutes === 5).map((j) => j.name);
    expect(names.indexOf("case-first-notice")).toBeGreaterThanOrEqual(0);
    expect(names.indexOf("case-first-notice")).toBeLessThan(names.indexOf("case-watch"));
  });

  it("leaves a case for the next tick when the budget cannot cover the whole family", async () => {
    const f = await family();
    const caseId = (await open(await newAlert(f.familyId)))?.id ?? "";
    await backdate(caseId, 31);
    sent = [];
    const watch = JOBS.find((j) => j.name === "case-watch");

    await watch?.run(pushEnv, Date.now(), new ExternalBudget(2));
    expect(sent).toHaveLength(0);
    expect((await caseRow(caseId))?.renotified_at).toBeNull();

    await watch?.run(pushEnv, Date.now(), new ExternalBudget(40));
    expect(sent).toHaveLength(3);
  });
});
