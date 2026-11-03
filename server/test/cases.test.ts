// Task 10 "引き継ぎ" in docs/plan.md: opening a case, the first accept wins, relays from the assignee
// only, the AI stopping once a family member has taken over, and the 30-minute watch.

import { createExecutionContext, createScheduledController, waitOnExecutionContext } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { http, HttpResponse } from "msw";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import { ExternalBudget } from "../src/budget";
import {
  acceptCase,
  aiGuidanceStopped,
  deliverAiReply,
  NO_REPLY_YET,
  openCase,
  relay,
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

  it("when the budget cannot cover the family, opens nothing and throws, and the retry opens and notifies", async () => {
    const f = await family();
    const alertId = await newAlert(f.familyId);

    await expect(open(alertId, new ExternalBudget(1))).rejects.toMatchObject({ name: "CaseNoticeDeferred" });
    expect(await casesFor(alertId)).toBe(0);
    expect(sent).toHaveLength(0);

    const opened = await open(alertId);
    expect(opened?.state).toBe("notified");
    expect(to(f.author)).toHaveLength(1);
    expect(to(f.sister)).toHaveLength(1);
  });

  it("when no family device took the notice, keeps no case and throws, and the retry notifies", async () => {
    const f = await family();
    const alertId = await newAlert(f.familyId);
    const apns = apnsFailsFor([f.author.token, f.sister.token]);

    await expect(open(alertId)).rejects.toMatchObject({ name: "CaseNoticeDeferred" });
    expect(await casesFor(alertId)).toBe(0);

    apns.ok = true;
    const opened = await open(alertId);
    expect(await casesFor(alertId)).toBe(1);
    expect(to(f.author)).toHaveLength(1);
    expect(to(f.sister)).toHaveLength(1);
    expect(to(f.author)[0]?.data.caseId).toBe(opened?.id);
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
  });
});

describe("accept", () => {
  it("of two near-simultaneous accepts, only one takes the case and the other gets 409 with the assignee's name", async () => {
    const f = await family();
    const opened = await open(await newAlert(f.familyId));
    const caseId = opened?.id ?? "";

    const [a, s] = await Promise.all([
      call("POST", `/cases/${caseId}/accept`, { deviceKey: f.author.deviceKey, env: pushEnv }),
      call("POST", `/cases/${caseId}/accept`, { deviceKey: f.sister.deviceKey, env: pushEnv }),
    ]);

    const statuses = [a.status, s.status].sort();
    expect(statuses).toEqual([200, 409]);
    const [winner, loser] = a.status === 200 ? [f.author, s] : [f.sister, a];
    const winnerName = winner === f.author ? "作者" : "妹";
    expect(await loser.json()).toEqual({
      error: "already_accepted",
      assignee: { memberId: winner.memberId, displayName: winnerName },
    });
    const row = await caseRow(caseId);
    expect(row?.state).toBe("accepted");
    expect(row?.assignee_member_id).toBe(winner.memberId);
  });

  it("accepting again by the assignee is not an error", async () => {
    const f = await family();
    const caseId = (await open(await newAlert(f.familyId)))?.id ?? "";
    await acceptCase(pushEnv, caseId, f.author.memberId);
    const again = await call("POST", `/cases/${caseId}/accept`, { deviceKey: f.author.deviceKey, env: pushEnv });
    expect(again.status).toBe(200);
    expect(((await again.json()) as { state: string }).state).toBe("accepted");
  });

  it("raises the flag that stops the AI's guidance for that case", async () => {
    const f = await family();
    const caseId = (await open(await newAlert(f.familyId)))?.id ?? "";
    expect(await aiGuidanceStopped(env, caseId)).toBe(false);

    await acceptCase(pushEnv, caseId, f.sister.memberId);

    expect(await aiGuidanceStopped(env, caseId)).toBe(true);
  });

  it("tells the protected person who is looking into it", async () => {
    const f = await family();
    const caseId = (await open(await newAlert(f.familyId)))?.id ?? "";
    sent = [];

    await acceptCase(pushEnv, caseId, f.sister.memberId);

    expect(to(f.mother).map((s) => s.body)).toEqual(["妹が見ています"]);
    // The others see "妹が対応中" on their card; no extra notification for them.
    expect(to(f.author)).toHaveLength(0);
  });

  it("the protected person cannot accept, and another family cannot see the case", async () => {
    const f = await family();
    const other = await createFamily("別の家族");
    const caseId = (await open(await newAlert(f.familyId)))?.id ?? "";

    const byMother = await call("POST", `/cases/${caseId}/accept`, { deviceKey: f.mother.deviceKey, env: pushEnv });
    expect(byMother.status).toBe(403);
    const byStranger = await call("POST", `/cases/${caseId}/accept`, { deviceKey: other.deviceKey, env: pushEnv });
    expect(byStranger.status).toBe(404);
    expect((await caseRow(caseId))?.state).toBe("notified");
  });
});

describe("the AI after a family member took over", () => {
  it("an AI answer still in flight when the case was accepted never reaches the protected person", async () => {
    const f = await family();
    const caseId = (await open(await newAlert(f.familyId)))?.id ?? "";

    // The AI started answering while the case was still only notified...
    const before = await aiGuidanceStopped(env, caseId);
    expect(before).toBe(false);
    // ...the sister accepted while it was working...
    await acceptCase(pushEnv, caseId, f.sister.memberId);
    // ...and its answer arrives afterwards.
    const outcome = await deliverAiReply(env, caseId, "送金はせず、いったん電話を切って");

    expect(outcome).toEqual({ delivered: false, assigneeName: "妹" });
    expect((await caseRow(caseId))?.ai_reply).toBeNull();
    const list = await call("GET", "/cases", { deviceKey: f.mother.deviceKey, env: pushEnv });
    const view = ((await list.json()) as { cases: Array<{ id: string; aiReply: string | null }> }).cases.find(
      (c) => c.id === caseId,
    );
    expect(view?.aiReply).toBeNull();
  });

  it("before anyone accepts, the AI's answer goes through and the family card shows it", async () => {
    const f = await family();
    const caseId = (await open(await newAlert(f.familyId)))?.id ?? "";

    expect(await deliverAiReply(env, caseId, "送金はせず、いったん電話を切って")).toEqual({ delivered: true });

    const list = await call("GET", "/cases", { deviceKey: f.author.deviceKey, env: pushEnv });
    const view = ((await list.json()) as { cases: Array<{ id: string; aiReply: string | null }> }).cases.find(
      (c) => c.id === caseId,
    );
    expect(view?.aiReply).toBe("送金はせず、いったん電話を切って");
  });
});

describe("relay", () => {
  it("only the assignee can send the protected person a reply", async () => {
    const f = await family();
    const caseId = (await open(await newAlert(f.familyId)))?.id ?? "";
    await acceptCase(pushEnv, caseId, f.author.memberId);

    const bySister = await call("POST", `/cases/${caseId}/relay`, {
      deviceKey: f.sister.deviceKey,
      body: { body: "私が電話するね" },
      env: pushEnv,
    });
    expect(bySister.status).toBe(403);
    await expect(relay(pushEnv, caseId, f.sister.memberId, "私が電話するね")).rejects.toMatchObject({ status: 403 });
    const relays = await env.DB.prepare("SELECT COUNT(*) AS n FROM relays WHERE case_id = ?").bind(caseId).first<{ n: number }>();
    expect(relays?.n).toBe(0);
  });

  it("nobody can relay before the case is accepted", async () => {
    const f = await family();
    const caseId = (await open(await newAlert(f.familyId)))?.id ?? "";
    const res = await call("POST", `/cases/${caseId}/relay`, {
      deviceKey: f.author.deviceKey,
      body: { body: "大丈夫？" },
      env: pushEnv,
    });
    expect(res.status).toBe(409);
  });

  it("the assignee's reply is kept as text, sent to the protected person, and listed with the sender's name", async () => {
    const f = await family();
    const caseId = (await open(await newAlert(f.familyId)))?.id ?? "";
    await acceptCase(pushEnv, caseId, f.author.memberId);
    sent = [];

    const res = await call("POST", `/cases/${caseId}/relay`, {
      deviceKey: f.author.deviceKey,
      body: { body: "  今から電話するから、お金は振り込まないで  " },
      env: pushEnv,
    });
    expect(res.status).toBe(201);

    expect(to(f.mother)).toEqual([
      expect.objectContaining({ title: "作者から", body: "今から電話するから、お金は振り込まないで" }),
    ]);
    expect(to(f.sister)).toHaveLength(0);
    const list = await call("GET", "/cases", { deviceKey: f.mother.deviceKey, env: pushEnv });
    const view = ((await list.json()) as { cases: Array<{ id: string; relays: unknown[] }> }).cases.find(
      (c) => c.id === caseId,
    );
    expect(view?.relays).toEqual([
      expect.objectContaining({
        fromMemberId: f.author.memberId,
        fromName: "作者",
        body: "今から電話するから、お金は振り込まないで",
      }),
    ]);
  });

  it("refuses an empty or very long reply", async () => {
    const f = await family();
    const caseId = (await open(await newAlert(f.familyId)))?.id ?? "";
    await acceptCase(pushEnv, caseId, f.author.memberId);
    for (const body of ["   ", "あ".repeat(201), 42]) {
      const res = await call("POST", `/cases/${caseId}/relay`, { deviceKey: f.author.deviceKey, body: { body }, env: pushEnv });
      expect(res.status).toBe(400);
    }
  });
});

describe("resolve", () => {
  it("only the assignee resolves, and a resolved case takes no more replies", async () => {
    const f = await family();
    const caseId = (await open(await newAlert(f.familyId)))?.id ?? "";
    await acceptCase(pushEnv, caseId, f.sister.memberId);

    await expect(resolveCase(pushEnv, caseId, f.author.memberId)).rejects.toMatchObject({ status: 403 });
    const res = await call("POST", `/cases/${caseId}/resolve`, { deviceKey: f.sister.deviceKey, env: pushEnv });
    expect(res.status).toBe(200);
    expect(((await res.json()) as { state: string }).state).toBe("resolved");
    expect((await caseRow(caseId))?.resolved_at).not.toBeNull();

    await expect(relay(pushEnv, caseId, f.sister.memberId, "もう一言")).rejects.toMatchObject({ status: 409 });
    const late = await call("POST", `/cases/${caseId}/accept`, { deviceKey: f.author.deviceKey, env: pushEnv });
    expect(late.status).toBe(409);
  });

  it("a case nobody accepted cannot be marked resolved", async () => {
    const f = await family();
    const caseId = (await open(await newAlert(f.familyId)))?.id ?? "";
    const res = await call("POST", `/cases/${caseId}/resolve`, { deviceKey: f.author.deviceKey, env: pushEnv });
    expect(res.status).toBe(409);
    expect((await caseRow(caseId))?.state).toBe("notified");
  });
});

describe("when the assignee leaves the family", () => {
  it("their accepted case goes back to nobody's, so another family member can take it", async () => {
    const f = await family();
    const caseId = (await open(await newAlert(f.familyId)))?.id ?? "";
    await acceptCase(pushEnv, caseId, f.sister.memberId);

    const left = await call("DELETE", "/members/me", { deviceKey: f.sister.deviceKey, env: pushEnv });
    expect(left.status).toBe(204);

    const row = await caseRow(caseId);
    expect(row).toMatchObject({ state: "notified", assignee_member_id: null, accepted_at: null });
    expect((await acceptCase(pushEnv, caseId, f.author.memberId)).assignee?.displayName).toBe("作者");
  });

  it("leaves resolved cases and other people's cases as they are", async () => {
    const f = await family();
    const done = (await open(await newAlert(f.familyId)))?.id ?? "";
    await acceptCase(pushEnv, done, f.sister.memberId);
    await resolveCase(pushEnv, done, f.sister.memberId);
    const authors = (await open(await newAlert(f.familyId)))?.id ?? "";
    await acceptCase(pushEnv, authors, f.author.memberId);

    await call("DELETE", "/members/me", { deviceKey: f.sister.deviceKey, env: pushEnv });

    expect((await caseRow(done))?.state).toBe("resolved");
    expect(await caseRow(authors)).toMatchObject({ state: "accepted", assignee_member_id: f.author.memberId });
  });
});

describe("GET /cases", () => {
  it("lists the family's cases with the alert, the assignee's name, and nothing from other families", async () => {
    const f = await family();
    const other = await family();
    const mine = (await open(await newAlert(f.familyId, { level: 2, summary: "宅配を名乗るSMS" })))?.id ?? "";
    const theirs = (await open(await newAlert(other.familyId)))?.id ?? "";
    await acceptCase(pushEnv, mine, f.sister.memberId);

    const res = await call("GET", "/cases", { deviceKey: f.author.deviceKey, env: pushEnv });
    expect(res.status).toBe(200);
    const { cases } = (await res.json()) as { cases: Array<Record<string, unknown>> };
    expect(cases.map((c) => c.id)).toEqual([mine]);
    expect(cases.map((c) => c.id)).not.toContain(theirs);
    expect(cases[0]).toMatchObject({
      state: "accepted",
      assignee: { memberId: f.sister.memberId, displayName: "妹" },
      alert: { level: 2, source: "call", summary: "宅配を名乗るSMS", reasons: ["警察を名乗り、口座の移し替えを求めた"] },
      relays: [],
    });
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

  it("after 30 minutes with nobody accepting, tells the protected person and notifies the family again, once", async () => {
    const f = await family();
    const caseId = (await open(await newAlert(f.familyId)))?.id ?? "";
    await backdate(caseId, 31);
    sent = [];

    await tick(Date.now());

    expect(to(f.mother).map((s) => s.body)).toEqual([NO_REPLY_YET]);
    expect(NO_REPLY_YET).toBe("家族から返事がまだ。急ぐなら電話して");
    expect(to(f.author)).toHaveLength(1);
    expect(to(f.sister)).toHaveLength(1);
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
    expect(view).toMatchObject({ state: "notified", assignee: null, resolvedAt: null });
    expect(typeof view?.renotifiedAt).toBe("string");
  });

  it("leaves alone a case accepted in time, and one that is not yet 30 minutes old", async () => {
    const f = await family();
    const accepted = (await open(await newAlert(f.familyId)))?.id ?? "";
    await acceptCase(pushEnv, accepted, f.author.memberId);
    await backdate(accepted, 40);
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

  it("a case released by an assignee who left is watched again: the rest of the family and the protected person hear once", async () => {
    const f = await family();
    const caseId = (await open(await newAlert(f.familyId)))?.id ?? "";
    // The watch already fired once before the sister accepted.
    await backdate(caseId, 40);
    await tick(Date.now());
    await acceptCase(pushEnv, caseId, f.sister.memberId);
    await call("DELETE", "/members/me", { deviceKey: f.sister.deviceKey, env: pushEnv });
    sent = [];

    await tick(Date.now());

    expect(to(f.mother).map((s) => s.body)).toEqual([NO_REPLY_YET]);
    expect(to(f.author)).toHaveLength(1);
    expect(to(f.sister)).toHaveLength(0);
    sent = [];
    await tick(Date.now() + 5 * 60_000);
    expect(sent).toHaveLength(0);
  });

  it("a released case younger than 30 minutes waits for the 30 minutes from the first notice", async () => {
    const f = await family();
    const caseId = (await open(await newAlert(f.familyId)))?.id ?? "";
    await acceptCase(pushEnv, caseId, f.sister.memberId);
    await call("DELETE", "/members/me", { deviceKey: f.sister.deviceKey, env: pushEnv });
    await backdate(caseId, 10);
    sent = [];

    await tick(Date.now());
    expect(sent).toHaveLength(0);

    await tick(Date.now() + 21 * 60_000);
    expect(to(f.mother).map((s) => s.body)).toEqual([NO_REPLY_YET]);
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
