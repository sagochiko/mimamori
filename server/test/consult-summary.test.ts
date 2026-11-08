// #271: the family's summary of a consultation, made by Managed Agents from fixed choices. Managed
// Agents is mocked with msw; nothing reaches Anthropic. What is checked: the session gets the level,
// the reasons, and the line the family already has, never her words; only a topic and a next step from
// our own lists come back, and anything else adds nothing; level 1 always reads "すぐ電話して確かめる";
// GET /cases carries the fixed line only; a consultation starts one only when the family was told of
// a sign at level 1 or 2, within the family's research starts for the day.

import { env } from "cloudflare:workers";
import { http, HttpResponse } from "msw";
import { beforeEach, describe, expect, it } from "vitest";
import {
  collectInvestigation,
  CONSULT_SUMMARY_AGENT_NAME,
  RESEARCH_ENVIRONMENT_NAME,
  startConsultSummary,
  watchInvestigations,
} from "../src/agents";
import { ExternalBudget } from "../src/budget";
import { RESEARCH_STARTS_PER_FAMILY_DAY } from "../src/claude-limit";
import { consult, type ClaudeConsult, type ConsultDeps } from "../src/consult";
import { parseSummary, SUMMARY_STEPS, SUMMARY_TOPICS, summaryLine } from "../src/consult-summary";
import { judgeByRules } from "../src/rules";
import { soundsSafe } from "../src/claude";
import { jstDate } from "../src/time";
import { call, createFamily, invite, join, type Created } from "./helpers";
import { network } from "./network";

const API = "https://api.anthropic.com/v1";
const T0 = Date.now();
const POLICE =
  "さっき警察から電話があって、あなたの口座が犯罪に使われているって。潔白を証明するために、LINE のビデオ通話で事情聴取をするから、ほかの人には言わないでって。お金を安全な口座に移すように言われた";

interface Seen {
  agents: Array<Record<string, unknown>>;
  environments: Array<Record<string, unknown>>;
  sessions: Array<{ id: string; body: Record<string, unknown> }>;
  deletes: string[];
}
let seen: Seen;
let statuses: Map<string, string>;
/** The report_summary input, by session id. */
let reports: Map<string, unknown>;

function mockApi(opts: { refuseSession?: boolean } = {}) {
  network.use(
    http.post(`${API}/agents`, async ({ request }) => {
      seen.agents.push((await request.json()) as Record<string, unknown>);
      return HttpResponse.json({ id: `agent_${seen.agents.length}` });
    }),
    http.post(`${API}/environments`, async ({ request }) => {
      seen.environments.push((await request.json()) as Record<string, unknown>);
      return HttpResponse.json({ id: `env_${seen.environments.length}` });
    }),
    http.post(`${API}/sessions`, async ({ request }) => {
      if (opts.refuseSession) return new HttpResponse(null, { status: 500 });
      const id = `sesn_${crypto.randomUUID()}`;
      seen.sessions.push({ id, body: (await request.json()) as Record<string, unknown> });
      statuses.set(id, "running");
      return HttpResponse.json({ id, status: "running" });
    }),
    http.get(`${API}/sessions/:id/events`, ({ params }) => {
      const id = String(params.id);
      const sent = seen.sessions.find((s) => s.id === id);
      const text = (sent?.body as { initial_events?: Array<{ content: Array<{ text: string }> }> } | undefined)
        ?.initial_events?.[0]?.content[0]?.text;
      const data: unknown[] = [];
      if (reports.has(id)) data.push({ type: "agent.custom_tool_use", name: "report_summary", input: reports.get(id) });
      data.push({ type: "user.message", content: [{ type: "text", text: text ?? "x" }] });
      return HttpResponse.json({ data, next_page: null });
    }),
    http.get(`${API}/sessions/:id`, ({ params }) => {
      const id = String(params.id);
      const status = statuses.get(id);
      if (status === undefined) return new HttpResponse(null, { status: 404 });
      return HttpResponse.json({ id, status });
    }),
    http.delete(`${API}/sessions/:id`, ({ params }) => {
      seen.deletes.push(String(params.id));
      statuses.delete(String(params.id));
      return HttpResponse.json({ id: params.id, type: "session_deleted" });
    }),
  );
}

beforeEach(async () => {
  seen = { agents: [], environments: [], sessions: [], deletes: [] };
  statuses = new Map();
  reports = new Map();
  await env.DB.prepare("DELETE FROM agent_resources").run();
});

const REASONS = ["警察を名乗る人から電話", "口座が犯罪に使われたと言われた"];
const INPUT = { level: 2 as const, reasons: REASONS, summary: "警察を名乗る電話の相談" };

async function seedConsult(
  family: Created,
  over: { level?: number; source?: string; notified?: number } = {},
): Promise<string> {
  const id = crypto.randomUUID();
  await env.DB.prepare(
    `INSERT INTO alerts (id, family_id, source, level, reasons, summary, created_at, notified)
     VALUES (?, ?, ?, ?, ?, '警察を名乗る電話の相談', ?, ?)`,
  )
    .bind(id, family.familyId, over.source ?? "consult", over.level ?? 2, JSON.stringify(REASONS), T0, over.notified ?? 1)
    .run();
  await env.DB.prepare(
    "INSERT INTO cases (id, family_id, alert_id, state, notified_at, family_notified_at) VALUES (?, ?, ?, 'notified', ?, ?)",
  )
    .bind(crypto.randomUUID(), family.familyId, id, T0, T0)
    .run();
  return id;
}

async function row(id: string) {
  return env.DB.prepare(
    "SELECT level, notified, investigation_session_id, investigated_at, summary_topic, summary_step FROM alerts WHERE id = ?",
  )
    .bind(id)
    .first<{
      level: number;
      notified: number;
      investigation_session_id: string | null;
      investigated_at: number | null;
      summary_topic: string | null;
      summary_step: string | null;
    }>();
}

async function startedFor(family: Created, level = 2): Promise<{ alertId: string; sessionId: string }> {
  const alertId = await seedConsult(family, { level });
  expect(await startConsultSummary(env, alertId, { ...INPUT, level: level as 1 | 2 }, new ExternalBudget(), T0)).toBe(true);
  return { alertId, sessionId: (await row(alertId))?.investigation_session_id ?? "" };
}

async function digestOf(family: Created, alertId: string): Promise<string | null | undefined> {
  const body = (await (await call("GET", "/cases", { deviceKey: family.deviceKey })).json()) as {
    cases: Array<{ alertId: string; alert: { digest?: string | null } }>;
  };
  return body.cases.find((c) => c.alertId === alertId)?.alert.digest;
}

describe("the choices", () => {
  it("has no choice that reads as safe or as nothing to do", () => {
    for (const label of [...Object.values(SUMMARY_TOPICS), ...Object.values(SUMMARY_STEPS)]) {
      expect(soundsSafe(label), label).toBe(false);
      expect(label).not.toMatch(/安全|安心|心配(ない|いらない|ありません)|大丈夫|問題(ない|ありません)/);
    }
  });

  it("reads only our own keys, and fixes the step at level 1", () => {
    expect(parseSummary({ topic: "money", next_step: "call_today" }, 2)).toEqual({ topic: "money", step: "call_today" });
    expect(parseSummary({ topic: "money", next_step: "call_today" }, 1)).toEqual({ topic: "money", step: "call_now" });
    for (const bad of [
      null,
      {},
      [],
      "money",
      { topic: "money" },
      { next_step: "call_now" },
      { topic: "safe", next_step: "call_now" },
      { topic: "money", next_step: "no_need" },
      { topic: SUMMARY_TOPICS.money, next_step: "call_now" },
      { topic: "toString", next_step: "call_now" },
      { topic: "__proto__", next_step: "call_now" },
    ]) {
      expect(parseSummary(bad, 2), JSON.stringify(bad)).toBeNull();
    }
  });

  it("makes the card's line from the keys alone", () => {
    expect(summaryLine("police", "call_today", 2)).toBe("警察を名乗る連絡 / 今日のうちに電話する");
    expect(summaryLine("police", "call_today", 1)).toBe("警察を名乗る連絡 / すぐ電話して確かめる");
    expect(summaryLine(null, null, 2)).toBeNull();
    expect(summaryLine("安全です", "call_now", 2)).toBeNull();
    expect(summaryLine("police", "安全です", 2)).toBeNull();
  });
});

describe("startConsultSummary", () => {
  it("makes its own agent with only the report tool, reuses the research environment, and sends no words of hers", async () => {
    mockApi();
    const family = await createFamily();
    const { sessionId } = await startedFor(family);
    expect(sessionId).toMatch(/^sesn_/);
    expect(CONSULT_SUMMARY_AGENT_NAME).not.toBe("research-agent-v2");
    expect(seen.environments).toHaveLength(1);
    const kept = await env.DB.prepare("SELECT name FROM agent_resources ORDER BY name").all<{ name: string }>();
    expect(kept.results.map((r) => r.name)).toEqual([CONSULT_SUMMARY_AGENT_NAME, RESEARCH_ENVIRONMENT_NAME].sort());

    const agent = seen.agents[0] as { tools: Array<Record<string, unknown>>; system: string };
    // No toolset at all: no web, no bash, no files.
    expect(agent.tools.map((t) => t.type)).toEqual(["custom"]);
    const tool = agent.tools[0] as {
      name: string;
      input_schema: { properties: Record<string, { enum?: string[] }>; required: string[] };
    };
    expect(tool.name).toBe("report_summary");
    expect(tool.input_schema.required.sort()).toEqual(["next_step", "topic"]);
    expect(Object.keys(tool.input_schema.properties).sort()).toEqual(["next_step", "topic"]);
    expect(tool.input_schema.properties.topic?.enum).toEqual(Object.keys(SUMMARY_TOPICS));
    expect(tool.input_schema.properties.next_step?.enum).toEqual(Object.keys(SUMMARY_STEPS));

    const text = (seen.sessions[0]?.body as { initial_events: Array<{ content: Array<{ text: string }> }> })
      .initial_events[0]?.content[0]?.text ?? "";
    expect(text).toContain("2段階");
    for (const r of REASONS) expect(text).toContain(r);

    // A second consultation reuses the agent and the environment.
    await startedFor(family);
    expect(seen.agents).toHaveLength(1);
    expect(seen.environments).toHaveLength(1);
  });

  it("does not start for a level 3 alert, another route, one that told no one, or one already started", async () => {
    mockApi();
    const family = await createFamily();
    const budget = new ExternalBudget();
    expect(await startConsultSummary(env, await seedConsult(family, { level: 3 }), { ...INPUT, level: 3 as never }, budget, T0)).toBe(false);
    expect(await startConsultSummary(env, await seedConsult(family, { source: "sms" }), INPUT, budget, T0)).toBe(false);
    expect(await startConsultSummary(env, await seedConsult(family, { notified: 0 }), INPUT, budget, T0)).toBe(false);
    const { alertId } = await startedFor(family);
    expect(await startConsultSummary(env, alertId, INPUT, budget, T0)).toBe(false);
    expect(seen.sessions).toHaveLength(1);
  });

  it("leaves the alert as it was when the API refuses", async () => {
    mockApi({ refuseSession: true });
    const family = await createFamily();
    const alertId = await seedConsult(family);
    expect(await startConsultSummary(env, alertId, INPUT, new ExternalBudget(), T0)).toBe(false);
    expect(await row(alertId)).toMatchObject({ level: 2, notified: 1, investigation_session_id: null, summary_topic: null });
  });
});

describe("reading the summary", () => {
  it("keeps the two keys, deletes the session, and the card shows the fixed line", async () => {
    mockApi();
    const family = await createFamily();
    const { alertId, sessionId } = await startedFor(family);
    expect(await digestOf(family, alertId)).toBeNull();
    statuses.set(sessionId, "idle");
    reports.set(sessionId, { topic: "police", next_step: "call_today" });
    expect(await collectInvestigation(env, sessionId, new ExternalBudget(), T0 + 60_000)).toBe("added");
    expect(await row(alertId)).toMatchObject({
      level: 2,
      notified: 1,
      summary_topic: "police",
      summary_step: "call_today",
      investigation_session_id: null,
    });
    expect(seen.deletes).toEqual([sessionId]);
    expect(await digestOf(family, alertId)).toBe("警察を名乗る連絡 / 今日のうちに電話する");
  });

  it("shows すぐ電話して確かめる at level 1 whatever the agent chose, also when the case became level 1 later", async () => {
    mockApi();
    const family = await createFamily();
    const one = await startedFor(family, 1);
    statuses.set(one.sessionId, "idle");
    reports.set(one.sessionId, { topic: "money", next_step: "call_today" });
    await collectInvestigation(env, one.sessionId, new ExternalBudget(), T0 + 60_000);
    expect((await row(one.alertId))?.summary_step).toBe("call_now");
    expect(await digestOf(family, one.alertId)).toBe("送金や振込 / すぐ電話して確かめる");

    const two = await startedFor(family, 2);
    statuses.set(two.sessionId, "idle");
    reports.set(two.sessionId, { topic: "money", next_step: "call_today" });
    await collectInvestigation(env, two.sessionId, new ExternalBudget(), T0 + 60_000);
    await env.DB.prepare("UPDATE alerts SET level = 1 WHERE id = ?").bind(two.alertId).run();
    expect(await digestOf(family, two.alertId)).toBe("送金や振込 / すぐ電話して確かめる");
  });

  it("adds nothing for an answer outside the choices, an empty one, or none", async () => {
    mockApi();
    const family = await createFamily();
    const answers: unknown[] = [
      { topic: "safe", next_step: "call_now" },
      { topic: "police", next_step: "心配ありません" },
      {},
      undefined,
    ];
    for (const answer of answers) {
      const { alertId, sessionId } = await startedFor(family);
      statuses.set(sessionId, "terminated");
      if (answer !== undefined) reports.set(sessionId, answer);
      expect(await collectInvestigation(env, sessionId, new ExternalBudget(), T0 + 60_000)).toBe("added");
      expect(await row(alertId)).toMatchObject({ level: 2, notified: 1, summary_topic: null, summary_step: null });
      expect(await digestOf(family, alertId)).toBeNull();
    }
  });

  it("adds nothing when the session is gone or was given up on, and the tick reads it too", async () => {
    mockApi();
    const family = await createFamily();
    const gone = await startedFor(family);
    statuses.delete(gone.sessionId);
    expect(await collectInvestigation(env, gone.sessionId, new ExternalBudget(), T0 + 60_000)).toBe("added");
    expect((await row(gone.alertId))?.summary_topic).toBeNull();

    const late = await startedFor(family);
    await watchInvestigations(env, T0 + 3 * 3600_000, new ExternalBudget());
    expect(await row(late.alertId)).toMatchObject({ summary_topic: null, notified: 1 });
    expect((await row(late.alertId))?.investigated_at).not.toBeNull();
  });

  it("does not let a research alert be read as a summary", async () => {
    mockApi();
    const family = await createFamily();
    const { alertId, sessionId } = await startedFor(family);
    await env.DB.prepare("UPDATE alerts SET source = 'sms' WHERE id = ?").bind(alertId).run();
    statuses.set(sessionId, "idle");
    reports.set(sessionId, { topic: "police", next_step: "call_now" });
    await collectInvestigation(env, sessionId, new ExternalBudget(), T0 + 60_000);
    expect((await row(alertId))?.summary_topic).toBeNull();
  });
});

describe("a consultation starts the summary", () => {
  async function mother(): Promise<{ owner: Created; member: { id: string; familyId: string; role: "protected"; displayName: string } }> {
    const owner = await createFamily("作者");
    const { code } = await invite(owner.deviceKey);
    const m = (await (await join(code, "protected", "母")).json()) as { memberId: string };
    return { owner, member: { id: m.memberId, familyId: owner.familyId, role: "protected", displayName: "母" } };
  }

  function deps(claude: ClaudeConsult | null): ConsultDeps & { started: string[]; later: Array<Promise<unknown>> } {
    const d = {
      started: [] as string[],
      later: [] as Array<Promise<unknown>>,
      judgeByRules,
      askClaude: async () => claude,
      openCase: async (e: Env, alertId: string, budget: ExternalBudget) => (await import("../src/cases")).openCase(e, alertId, budget),
      now: () => T0,
      summarize: async (_e: Env, alertId: string) => {
        d.started.push(alertId);
        return true;
      },
      defer: (task: Promise<unknown>) => {
        d.later.push(task);
      },
    };
    return d;
  }

  const help: ClaudeConsult = {
    kind: "help",
    level: 3,
    reasons: [],
    basis: "",
    action: "設定の「一般」から「iPhone ストレージ」を開くと、空きを作れます",
    handoff: false,
    injection_suspected: false,
    topic: "ストレージの空きの相談",
  };

  it("starts one, after the answer, for the fake-police script at level 1", async () => {
    const { member } = await mother();
    const d = deps(null);
    await consult(env, member, POLICE, new ExternalBudget(), d);
    await Promise.all(d.later);
    const alert = await env.DB.prepare("SELECT id, level FROM alerts WHERE family_id = ?")
      .bind(member.familyId)
      .first<{ id: string; level: number }>();
    expect(alert?.level).toBe(1);
    expect(d.started).toEqual([alert?.id]);
    expect(d.later).toHaveLength(1);
  });

  it("starts none for level 3, for a topic the AI only hands to the family, or when the AI could not answer", async () => {
    const { member } = await mother();
    const d = deps(help);
    await consult(env, member, "iPhone の空きを作りたい", new ExternalBudget(), d);
    await consult(env, member, "振込のやり方を教えて", new ExternalBudget(), d);
    const failed = deps(null);
    await consult(env, member, "このアプリの使い方がわからない", new ExternalBudget(), failed);
    await Promise.all([...d.later, ...failed.later]);
    expect(d.started).toEqual([]);
    expect(failed.started).toEqual([]);
  });

  it("starts none past the family's research starts for the day", async () => {
    const { member } = await mother();
    await env.DB.prepare("INSERT INTO claude_daily (family_id, day, claude_calls, research_starts) VALUES (?, ?, 0, ?)")
      .bind(member.familyId, jstDate(T0), RESEARCH_STARTS_PER_FAMILY_DAY)
      .run();
    const d = deps(null);
    await consult(env, member, POLICE, new ExternalBudget(), d);
    await Promise.all(d.later);
    expect(d.started).toEqual([]);
  });
});
