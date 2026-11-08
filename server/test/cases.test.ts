// Task 10 "家族への知らせと解決" in docs/plan.md: opening a case, "解決" by any family member, the
// accept and relay routes being gone, and the 30-minute watch.

import { createExecutionContext, createScheduledController, waitOnExecutionContext } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { http, HttpResponse } from "msw";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { countD1, ExternalBudget } from "../src/budget";
import {
  CLAIM_TTL_MS,
  familyBadge,
  NO_REPLY_YET,
  NOT_REACHED,
  NOT_RESOLVED_YET,
  openCase,
  recordAiReply,
  resolveCase,
  sendFirstNotices,
  tellFamilyHeavier,
  UNANSWERED_AFTER_MS,
  watchUnanswered,
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
  const pair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, [
    "sign",
  ])) as CryptoKeyPair;
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

// The tick runs every 5-minute job, the missed-smile notice among them. A family whose protected member
// joined before today's smile deadline (5 to 12 JST) gets that notice once a tick passes the deadline,
// so ticks a few minutes ahead, run shortly before the deadline, sent it to every family in this file
// (#160). The clock stays at 15:00 JST, after every deadline, so no family here is ever due for it.
const AFTER_EVERY_SMILE_DEADLINE = Date.parse("2026-11-06T15:00:00+09:00");

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(AFTER_EVERY_SMILE_DEADLINE);
  resetApnsJwtCache();
  sent = [];
  network.use(
    http.post(`${SANDBOX}/3/device/:token`, async ({ request, params }) => {
      const payload = (await request.json()) as { aps: { alert: { title?: string; body: string } } } & Record<
        string,
        unknown
      >;
      const { aps, ...data } = payload;
      sent.push({ token: String(params.token), title: aps.alert.title, body: aps.alert.body, data });
      return new HttpResponse(null, { status: 200 });
    }),
  );
});

afterEach(() => {
  vi.useRealTimers();
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

async function newAlert(
  familyId: string,
  opts: { level?: 1 | 2 | 3; summary?: string; source?: "consult" | "sms" | "gmail" | "page" | "dns" } = {},
): Promise<string> {
  const id = crypto.randomUUID();
  await env.DB.prepare(
    "INSERT INTO alerts (id, family_id, source, level, reasons, summary, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
  )
    .bind(
      id,
      familyId,
      opts.source ?? "consult",
      opts.level ?? 1,
      JSON.stringify(["警察を名乗り、口座の移し替えを求めた"]),
      opts.summary ?? "警察を名乗る電話の相談",
      Date.now(),
    )
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
  return env.DB.prepare("SELECT id, state, family_notified_at, family_notice_claimed_at FROM cases WHERE alert_id = ?")
    .bind(alertId)
    .first<{ id: string; state: string; family_notified_at: number | null; family_notice_claimed_at: number | null }>();
}

/** Another caller's claim on sending the case's first notice, taken at `at`. */
async function claimedBy(alertId: string, at: number): Promise<void> {
  await env.DB.prepare("UPDATE cases SET family_notice_claimed_at = ? WHERE alert_id = ?").bind(at, alertId).run();
}

async function casesFor(alertId: string): Promise<number> {
  const row = await env.DB.prepare("SELECT COUNT(*) AS n FROM cases WHERE alert_id = ?")
    .bind(alertId)
    .first<{ n: number }>();
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

describe("familyBadge", () => {
  it("names the level in words the family can read, never as a number or as safe", () => {
    expect([1, 2, 3].map(familyBadge)).toEqual(["危ない", "確かめて", "念のため"]);
    for (const word of [1, 2, 3].map(familyBadge)) {
      expect(word).not.toMatch(/段階|安全|大丈夫|問題な|心配な/);
    }
  });
});

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
    const n = await env.DB.prepare("SELECT COUNT(*) AS n FROM cases WHERE alert_id = ?")
      .bind(alertId)
      .first<{ n: number }>();
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

  it("when no family member has a device to notify, keeps the case untold and throws, and the tick tells a device registered later", async () => {
    const f = await family();
    await env.DB.prepare("UPDATE members SET apns_token = NULL WHERE family_id = ? AND role = 'family'")
      .bind(f.familyId)
      .run();
    const alertId = await newAlert(f.familyId);

    // Nobody was told, so it is not told (#60): the protected person must not hear "家族に伝えました".
    await expect(open(alertId, new ExternalBudget(0))).rejects.toMatchObject({
      name: "CaseNoticeDeferred",
      reason: "not_delivered",
    });
    expect((await caseOf(alertId))?.state).toBe("notified");
    expect((await caseOf(alertId))?.family_notified_at).toBeNull();

    await env.DB.prepare("UPDATE members SET apns_token = ?, apns_env = 'sandbox' WHERE id = ?")
      .bind(f.sister.token, f.sister.memberId)
      .run();
    sent = [];
    await tick(Date.now());
    expect(to(f.sister)).toEqual([expect.objectContaining({ title: "危ない", body: "警察を名乗る電話の相談" })]);
    expect((await caseOf(alertId))?.family_notified_at).not.toBeNull();
  });
});

// #64: the claim on sending the first notice is its own column, so a notice still being sent is
// never read as told, by the protected person's answer, her screen, or the 30-minute watch.
describe("the claim on the first notice", () => {
  it("while the notice is being sent the case is claimed but not told, and reads as told once a device took it", async () => {
    const f = await family();
    const alertId = await newAlert(f.familyId);
    const during: unknown[] = [];
    network.use(
      http.post(`${SANDBOX}/3/device/:token`, async ({ request }) => {
        const { caseId } = (await request.json()) as { caseId: string };
        const row = await env.DB.prepare("SELECT family_notified_at, family_notice_claimed_at FROM cases WHERE id = ?")
          .bind(caseId)
          .first<{ family_notified_at: number | null; family_notice_claimed_at: number | null }>();
        const list = await call("GET", "/cases", { deviceKey: f.mother.deviceKey, env: pushEnv });
        const { cases } = (await list.json()) as { cases: Array<{ id: string; familyNotifiedAt: string | null }> };
        const view = cases.find((c) => c.id === caseId);
        during.push({ ...row, familyNotifiedAt: view === undefined ? "missing" : view.familyNotifiedAt });
        return new HttpResponse(null, { status: 200 });
      }),
    );

    await open(alertId);

    expect(during).toEqual([
      { family_notified_at: null, family_notice_claimed_at: expect.any(Number), familyNotifiedAt: null },
      { family_notified_at: null, family_notice_claimed_at: expect.any(Number), familyNotifiedAt: null },
    ]);
    expect(await caseOf(alertId)).toMatchObject({
      family_notified_at: expect.any(Number),
      family_notice_claimed_at: null,
    });
  });

  it("when the budget or APNs fails, only the claim is let go and the case stays untold", async () => {
    const f = await family();
    const alertId = await newAlert(f.familyId);

    await expect(open(alertId, new ExternalBudget(1))).rejects.toMatchObject({ reason: "no_budget" });
    expect(await caseOf(alertId)).toMatchObject({ family_notified_at: null, family_notice_claimed_at: null });

    const apns = apnsFailsFor([f.author.token, f.sister.token]);
    await expect(open(alertId)).rejects.toMatchObject({ reason: "not_delivered" });
    expect(await caseOf(alertId)).toMatchObject({ family_notified_at: null, family_notice_claimed_at: null });

    apns.ok = true;
    await open(alertId);
    expect(to(f.author)).toHaveLength(1);
    expect(await caseOf(alertId)).toMatchObject({
      family_notified_at: expect.any(Number),
      family_notice_claimed_at: null,
    });
  });

  it("while another caller is sending, openCase sends nothing, takes no ticket, does not throw, and the case reads untold", async () => {
    const f = await family();
    const alertId = await newAlert(f.familyId);
    await expect(open(alertId, new ExternalBudget(1))).rejects.toMatchObject({ name: "CaseNoticeDeferred" });
    const at = Date.now();
    await claimedBy(alertId, at);
    const budget = new ExternalBudget(40);

    const opened = await open(alertId, budget);

    expect(sent).toHaveLength(0);
    expect(budget.remaining).toBe(40);
    expect(opened?.familyNotifiedAt).toBeNull();
    // The other caller's claim is left alone; that caller lets go of it.
    expect(await caseOf(alertId)).toMatchObject({ family_notified_at: null, family_notice_claimed_at: at });
  });

  it("the tick takes over a claim older than CLAIM_TTL_MS, as from a Worker that stopped mid-send, and leaves a newer one alone", async () => {
    const f = await family();
    const alertId = await newAlert(f.familyId);
    await expect(open(alertId, new ExternalBudget(1))).rejects.toMatchObject({ name: "CaseNoticeDeferred" });

    const recent = Date.now() - CLAIM_TTL_MS + 60_000;
    await claimedBy(alertId, recent);
    await tick(Date.now());
    expect(to(f.author)).toHaveLength(0);
    expect(to(f.sister)).toHaveLength(0);
    expect(await caseOf(alertId)).toMatchObject({ family_notified_at: null, family_notice_claimed_at: recent });

    await claimedBy(alertId, Date.now() - CLAIM_TTL_MS - 1000);
    await tick(Date.now());
    expect(to(f.author)).toHaveLength(1);
    expect(to(f.sister)).toHaveLength(1);
    expect(await caseOf(alertId)).toMatchObject({
      family_notified_at: expect.any(Number),
      family_notice_claimed_at: null,
    });
  });

  it("a heavier notice that no device took puts the case back on the first notice's retry, with no claim left", async () => {
    const f = await family();
    const alertId = await newAlert(f.familyId, { level: 2 });
    const caseId = (await open(alertId))?.id ?? "";
    // No path leaves a claim beside the mark; one put there by hand must not hold back the retry either.
    await env.DB.prepare("UPDATE cases SET family_notice_claimed_at = ? WHERE id = ?").bind(Date.now(), caseId).run();
    await env.DB.prepare("UPDATE alerts SET level = 1 WHERE id = ?").bind(alertId).run();
    const apns = apnsFailsFor([f.author.token, f.sister.token]);
    const errors = vi.spyOn(console, "error").mockImplementation(() => {});
    try {
      expect(await tellFamilyHeavier(pushEnv, caseId, new ExternalBudget())).toBe(false);
    } finally {
      errors.mockRestore();
    }
    expect(await caseOf(alertId)).toMatchObject({ family_notified_at: null, family_notice_claimed_at: null });

    apns.ok = true;
    sent = [];
    await tick(Date.now());
    expect(to(f.author)).toEqual([expect.objectContaining({ title: "危ない" })]);
    expect(to(f.sister)).toEqual([expect.objectContaining({ title: "危ない" })]);
  });

  // #49 (the 4th line): a case the family already resolved is not sent its first notice by a retry.
  it("a retried openCase on a case the family resolved before the first notice got through sends nothing", async () => {
    const f = await family();
    const alertId = await newAlert(f.familyId);
    await expect(open(alertId, new ExternalBudget(1))).rejects.toMatchObject({ reason: "no_budget" });
    const caseId = (await caseOf(alertId))?.id ?? "";
    // The sister saw the case on her list and talked with the mother before any notice reached her.
    await resolveCase(pushEnv, caseId, f.sister.memberId);
    sent = [];
    const budget = new ExternalBudget(40);

    const opened = await open(alertId, budget);

    expect(sent).toHaveLength(0);
    expect(budget.remaining).toBe(40);
    expect(opened).toMatchObject({ state: "resolved", familyNotifiedAt: null });
    expect(await caseOf(alertId)).toMatchObject({ family_notified_at: null, family_notice_claimed_at: null });
  });

  // #49 (the 6th line): the queue and the tick reaching for the same first notice at once send it once.
  it("openCase and the tick sending the same first notice at once tell each family device once", async () => {
    const f = await family();
    const alertId = await newAlert(f.familyId);
    await expect(open(alertId, new ExternalBudget(1))).rejects.toMatchObject({ reason: "no_budget" });
    sent = [];

    const [opened] = await Promise.allSettled([open(alertId), tick(Date.now())]);

    // Whichever lost the claim returns without throwing; the winner told the family.
    expect(opened.status).toBe("fulfilled");
    expect(to(f.author)).toHaveLength(1);
    expect(to(f.sister)).toHaveLength(1);
    expect(to(f.mother)).toHaveLength(0);
    expect(await caseOf(alertId)).toMatchObject({
      family_notified_at: expect.any(Number),
      family_notice_claimed_at: null,
    });
  });
});

// #49 (the 6th line): the tick's retry of first notices stops at the first case the budget cannot cover.
describe("the first-notice retry and the tick's budget", () => {
  it("stops at the first family the budget cannot cover and leaves every older case unclaimed for the next tick", async () => {
    // Untold cases left by earlier tests in this file would take part; they are marked told here.
    await env.DB.prepare("UPDATE cases SET family_notified_at = ? WHERE family_notified_at IS NULL")
      .bind(Date.now())
      .run();
    const now = Date.now();
    const untold = async (familyId: string, minutesAgo: number) => {
      const alertId = await newAlert(familyId);
      await env.DB.prepare(
        "INSERT INTO cases (id, family_id, alert_id, state, notified_at) VALUES (?, ?, ?, 'notified', ?)",
      )
        .bind(crypto.randomUUID(), familyId, alertId, now - minutesAgo * 60_000)
        .run();
      return alertId;
    };
    // Newest first: a (2 family devices), then b (2), then c (1, the sister has no device).
    const a = await family();
    const b = await family();
    const c = await family();
    await env.DB.prepare("UPDATE members SET apns_token = NULL WHERE id = ?").bind(c.sister.memberId).run();
    const caseA = await untold(a.familyId, 1);
    const caseB = await untold(b.familyId, 2);
    const caseC = await untold(c.familyId, 3);
    sent = [];
    // Enough for a, and one left over: not enough for b, but enough for c if the retry went on past b.
    const budget = new ExternalBudget(3);

    await sendFirstNotices(pushEnv, now, budget);

    expect(to(a.author)).toHaveLength(1);
    expect(to(a.sister)).toHaveLength(1);
    expect(to(b.author)).toHaveLength(0);
    expect(to(c.author)).toHaveLength(0);
    expect(budget.remaining).toBe(1);
    expect(await caseOf(caseA)).toMatchObject({ family_notified_at: expect.any(Number) });
    for (const alertId of [caseB, caseC]) {
      expect(await caseOf(alertId)).toMatchObject({ family_notified_at: null, family_notice_claimed_at: null });
    }

    // The next tick, with its own budget, picks them up.
    sent = [];
    await sendFirstNotices(pushEnv, now + 5 * 60_000, new ExternalBudget(40));
    expect(to(b.author)).toHaveLength(1);
    expect(to(b.sister)).toHaveLength(1);
    expect(to(c.author)).toHaveLength(1);
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
    const relays = await env.DB.prepare("SELECT COUNT(*) AS n FROM relays WHERE case_id = ?")
      .bind(caseId)
      .first<{ n: number }>();
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
    const views = [
      (await a.json()) as { resolvedBy: { memberId: string } },
      (await s.json()) as { resolvedBy: { memberId: string } },
    ];
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
    const mine =
      (await open(await newAlert(f.familyId, { level: 2, summary: "SMS 宅配の不在の知らせをかたっている" })))?.id ?? "";
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
        source: "consult",
        summary: "SMS 宅配の不在の知らせをかたっている",
        reasons: ["警察を名乗り、口座の移し替えを求めた"],
      },
      aiReply: null,
    });
    // Nothing of the hand-off is left in the shape.
    for (const gone of ["assignee", "assigneeMemberId", "acceptedAt", "relays"])
      expect(cases[0]).not.toHaveProperty(gone);
    expect(typeof cases[0]?.notifiedAt).toBe("string");
  });

  // #60: the protected person's screen says "家族に届いていません" while no family device took it, so
  // every case carries when the family was first told, or null.
  it("carries familyNotifiedAt: when the family was told, or null while no family device took it", async () => {
    const f = await family();
    const told = (await open(await newAlert(f.familyId)))?.id ?? "";
    const untoldAlert = await newAlert(f.familyId);
    const state = apnsFailsFor([f.author.token, f.sister.token]);
    await expect(open(untoldAlert)).rejects.toMatchObject({ name: "CaseNoticeDeferred" });
    const untold = (await caseOf(untoldAlert))?.id ?? "";

    const read = async () => {
      const res = await call("GET", "/cases", { deviceKey: f.mother.deviceKey, env: pushEnv });
      return ((await res.json()) as { cases: Array<Record<string, unknown>> }).cases;
    };
    const before = await read();
    const toldAt = before.find((c) => c.id === told)?.familyNotifiedAt;
    expect(typeof toldAt).toBe("string");
    expect(new Date(String(toldAt)).toISOString()).toBe(toldAt);
    expect(before.find((c) => c.id === untold)).toHaveProperty("familyNotifiedAt", null);

    // The 5-minute tick gets it through: the case reads as told again.
    state.ok = true;
    await tick(Date.now());
    expect(typeof (await read()).find((c) => c.id === untold)?.familyNotifiedAt).toBe("string");
  });

  it("the case that resolve answers with has the same familyNotifiedAt", async () => {
    const f = await family();
    const caseId = (await open(await newAlert(f.familyId)))?.id ?? "";
    const res = await call("POST", `/cases/${caseId}/resolve`, { deviceKey: f.author.deviceKey, env: pushEnv });
    expect(typeof ((await res.json()) as Record<string, unknown>).familyNotifiedAt).toBe("string");
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
    expect(to(f.author)).toEqual([
      expect.objectContaining({ title: "まだ解決していません", body: "警察を名乗る電話の相談" }),
    ]);
    expect(to(f.sister)).toEqual([expect.objectContaining({ title: NOT_RESOLVED_YET })]);
    expect((await caseRow(caseId))?.renotified_at).not.toBeNull();

    // Later ticks do not notify again.
    sent = [];
    await tick(Date.now() + 5 * 60_000);
    await tick(Date.now() + 10 * 60_000);
    expect(sent).toHaveLength(0);
  });

  // #239: her strip shows only her own consultations, so a reminder about a case found by the app
  // would be a "急ぐなら電話して" about nothing on her screen. The family is reminded as before.
  it.each(["gmail", "sms", "page", "dns"] as const)(
    "for a case the app found (%s), reminds the family but not the protected person",
    async (source) => {
      const f = await family();
      const caseId = (await open(await newAlert(f.familyId, { source, summary: "メール 未上場株に誘う" })))?.id ?? "";
      await backdate(caseId, 31);
      sent = [];

      await tick(Date.now());

      expect(to(f.mother)).toEqual([]);
      expect(to(f.author)).toEqual([
        expect.objectContaining({ title: NOT_RESOLVED_YET, body: "メール 未上場株に誘う" }),
      ]);
      expect(to(f.sister)).toEqual([expect.objectContaining({ title: NOT_RESOLVED_YET })]);
      expect((await caseRow(caseId))?.renotified_at).not.toBeNull();
    },
  );

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
    expect(to(f.author)[0]).toMatchObject({ title: "危ない", body: "警察を名乗る電話の相談" });
    expect(to(f.author)[0]?.data.caseId).toBe((await caseOf(alertId))?.id);
    sent = [];
    await tick(Date.now() + 5 * 60_000);
    expect(sent).toHaveLength(0);
  });

  it("cases of a family with no device do not crowd out another family's untold case from the retry", async () => {
    // A family whose members registered no device: 25 untold cases, newer than the other family's.
    const deviceless = await family();
    await env.DB.prepare("UPDATE members SET apns_token = NULL WHERE family_id = ? AND role = 'family'")
      .bind(deviceless.familyId)
      .run();
    const now = Date.now();
    for (let i = 0; i < 25; i++) {
      const alertId = await newAlert(deviceless.familyId);
      await env.DB.prepare(
        "INSERT INTO cases (id, family_id, alert_id, state, notified_at) VALUES (?, ?, ?, 'notified', ?)",
      )
        .bind(crypto.randomUUID(), deviceless.familyId, alertId, now - 60_000 + i)
        .run();
    }
    // The other family's notice failed on APNs ten minutes ago.
    const f = await family();
    const alertId = await newAlert(f.familyId);
    const apns = apnsFailsFor([f.author.token, f.sister.token]);
    await expect(open(alertId)).rejects.toMatchObject({ name: "CaseNoticeDeferred" });
    await backdate((await caseOf(alertId))?.id ?? "", 10);
    apns.ok = true;
    sent = [];

    await tick(now);

    expect(to(f.author)).toHaveLength(1);
    expect(to(f.sister)).toHaveLength(1);
    expect((await caseOf(alertId))?.family_notified_at).not.toBeNull();
  });

  it("an untold case is still watched: after 30 minutes the protected person hears it did not reach the family, even while the family's devices fail", async () => {
    const f = await family();
    const alertId = await newAlert(f.familyId);
    apnsFailsFor([f.author.token, f.sister.token]);
    await expect(open(alertId)).rejects.toMatchObject({ name: "CaseNoticeDeferred" });
    await backdate((await caseOf(alertId))?.id ?? "", 31);
    sent = [];

    await tick(Date.now());

    // Not "家族から返事がまだ": the family never got it (#60).
    expect(to(f.mother).map((s) => s.body)).toEqual([NOT_REACHED]);
    expect(NOT_REACHED).toBe("家族に届いていません。急ぐなら電話して");
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

// #178: D1's limits page gives Free 50 queries per Worker invocation. One 5-minute tick, every job
// together, stays within it, and what does not fit is picked up by the next tick.
describe("the tick's D1 calls", () => {
  const D1_LIMIT_PER_INVOCATION = 50;

  /**
   * pushEnv with a DB that counts the calls the tick makes. A prepared statement is counted when it is
   * prepared, an upper bound since every statement here runs once; a batch is one call however many
   * statements it carries.
   */
  function counted(): { env: Env; calls: () => number } {
    let n = 0;
    const db = pushEnv.DB;
    const DB = {
      prepare: (query: string) => {
        n += 1;
        return db.prepare(query);
      },
      batch: (statements: D1PreparedStatement[]) => {
        n += 1 - statements.length;
        return db.batch(statements);
      },
      exec: (query: string) => {
        n += 1;
        return db.exec(query);
      },
      withSession: db.withSession.bind(db),
      dump: db.dump.bind(db),
    } as unknown as D1Database;
    return { env: { ...pushEnv, DB }, calls: () => n };
  }

  async function countedTick(scheduledTime: number): Promise<number> {
    const { env: tickEnv, calls } = counted();
    const ctx = createExecutionContext();
    await worker.scheduled(createScheduledController({ scheduledTime, cron: "*/5 * * * *" }), tickEnv, ctx);
    await waitOnExecutionContext(ctx);
    return calls();
  }

  beforeEach(async () => {
    await env.DB.prepare("DELETE FROM cases").run();
  });

  it("sends twenty untold first notices over several ticks, each tick within the limit", async () => {
    const f = await family();
    const now = Date.now();
    const alertIds: string[] = [];
    for (let i = 0; i < 20; i++) {
      const alertId = await newAlert(f.familyId);
      await env.DB.prepare(
        "INSERT INTO cases (id, family_id, alert_id, state, notified_at) VALUES (?, ?, ?, 'notified', ?)",
      )
        .bind(crypto.randomUUID(), f.familyId, alertId, now - i * 1000)
        .run();
      alertIds.push(alertId);
    }
    sent = [];

    const first = await countedTick(now);
    expect(first).toBeLessThanOrEqual(D1_LIMIT_PER_INVOCATION);
    const rows = await Promise.all(alertIds.map(caseOf));
    const told = rows.filter((r) => r?.family_notified_at !== null);
    expect(told.length).toBeGreaterThan(0);
    expect(told.length).toBeLessThan(20);
    // The rest are neither told nor held by a claim, so the next tick takes them at once.
    for (const r of rows.filter((r) => r?.family_notified_at === null)) {
      expect(r?.family_notice_claimed_at).toBeNull();
    }

    // At most half of the tick's calls go to first notices (four cases), so twenty take five ticks.
    for (let t = 1; t <= 4; t++) {
      expect(await countedTick(now + t * 5 * 60_000)).toBeLessThanOrEqual(D1_LIMIT_PER_INVOCATION);
    }
    for (const alertId of alertIds) {
      expect(await caseOf(alertId)).toMatchObject({ family_notified_at: expect.any(Number) });
    }
    // Every case once to each family device, never twice.
    expect(to(f.author)).toHaveLength(20);
    expect(to(f.sister)).toHaveLength(20);
  });

  /** A case the family was told of 40 minutes ago and has not resolved, due for the 30-minute watch. */
  async function dueForWatch(familyId: string, now: number): Promise<string> {
    const caseId = crypto.randomUUID();
    await env.DB.prepare(
      "INSERT INTO cases (id, family_id, alert_id, state, notified_at, family_notified_at) VALUES (?, ?, ?, 'notified', ?, ?)",
    )
      .bind(caseId, familyId, await newAlert(familyId), now - 40 * 60_000, now - 40 * 60_000)
      .run();
    return caseId;
  }

  it("still runs the watch when first notices keep failing, so she hears 急ぐなら電話して", async () => {
    const now = Date.now();
    // A family whose devices APNs keeps refusing (not 410), with twenty untold cases from today.
    const failing = await family();
    apnsFailsFor([failing.author.token, failing.sister.token, failing.mother.token]);
    for (let i = 0; i < 20; i++) {
      await env.DB.prepare(
        "INSERT INTO cases (id, family_id, alert_id, state, notified_at) VALUES (?, ?, ?, 'notified', ?)",
      )
        .bind(crypto.randomUUID(), failing.familyId, await newAlert(failing.familyId), now - i * 1000)
        .run();
    }
    const f = await family();
    const caseId = await dueForWatch(f.familyId, now);
    sent = [];

    expect(await countedTick(now)).toBeLessThanOrEqual(D1_LIMIT_PER_INVOCATION);

    expect(to(f.mother).map((s) => s.body)).toEqual([NO_REPLY_YET]);
    expect(to(f.author)).toEqual([expect.objectContaining({ title: NOT_RESOLVED_YET })]);
    expect((await caseRow(caseId))?.renotified_at).not.toBeNull();
  });

  it("plans one reminder for exactly the D1 calls it takes, her notice and the family's", async () => {
    const now = Date.now();
    const f = await family();
    const caseId = await dueForWatch(f.familyId, now);
    sent = [];

    // One short of the lookup and one reminder, so the check before the lookup returns: nothing is claimed.
    const short = new ExternalBudget(40, 4);
    await watchUnanswered({ ...pushEnv, DB: countD1(pushEnv.DB, short) }, now, short);
    expect(sent).toHaveLength(0);
    expect((await caseRow(caseId))?.renotified_at).toBeNull();

    // The lookup and one reminder: the members, the claim, her tokens, the family's tokens.
    const exact = new ExternalBudget(40, 5);
    await watchUnanswered({ ...pushEnv, DB: countD1(pushEnv.DB, exact) }, now, exact);
    expect(to(f.mother).map((s) => s.body)).toEqual([NO_REPLY_YET]);
    expect(to(f.author)).toHaveLength(1);
    expect(to(f.sister)).toHaveLength(1);
    expect(exact.d1Remaining).toBe(0);
  });

  it("reminds about twenty unresolved cases over several ticks, each tick within the limit", async () => {
    const now = Date.now();
    const caseIds: string[] = [];
    // A family of one each, so the outside-call budget (40) is not what stops the tick.
    for (let i = 0; i < 20; i++) {
      const author = await createFamily("作者");
      await env.DB.prepare("UPDATE members SET apns_token = ?, apns_env = 'sandbox' WHERE id = ?")
        .bind(hexToken(), author.memberId)
        .run();
      const alertId = await newAlert(author.familyId);
      const caseId = crypto.randomUUID();
      await env.DB.prepare(
        "INSERT INTO cases (id, family_id, alert_id, state, notified_at, family_notified_at) VALUES (?, ?, ?, 'notified', ?, ?)",
      )
        .bind(caseId, author.familyId, alertId, now - 40 * 60_000 - i * 1000, now - 40 * 60_000)
        .run();
      caseIds.push(caseId);
    }
    sent = [];

    expect(await countedTick(now)).toBeLessThanOrEqual(D1_LIMIT_PER_INVOCATION);
    const reminded = async () =>
      (await Promise.all(caseIds.map(caseRow))).filter((r) => r?.renotified_at !== null).length;
    const afterFirst = await reminded();
    expect(afterFirst).toBeGreaterThan(0);
    expect(afterFirst).toBeLessThan(20);

    for (let t = 1; t <= 3; t++) {
      expect(await countedTick(now + t * 5 * 60_000)).toBeLessThanOrEqual(D1_LIMIT_PER_INVOCATION);
    }
    expect(await reminded()).toBe(20);
    expect(sent).toHaveLength(20);
  });
});
