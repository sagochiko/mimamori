// The judge queue (task 6 in docs/plan.md). Routes that answer at once with the rules (SMS, pages,
// consultations) put a job here with enqueueJudge; this consumer lays Claude's judgment over the
// rule result, writes the alerts row, tells the mother and the family, and opens a case.
//
// Who gets told depends only on the level and the family's members, never on Claude's answer or the
// received text (.claude/rules/server.md).
//
// Not wired yet: judgeByRules comes from src/rules/ (#6) and openCase from src/cases.ts (#8). Until
// they merge, defaultJudgeDeps throws for both, so jobs are retried rather than judged half-way.

import { ExternalBudget } from "./budget";
import {
  ALERT_SOURCES,
  decide,
  requestClaudeJudgment,
  type AlertSource,
  type ClaudeJudgment,
  type Level,
  type RuleInput,
  type RuleResult,
} from "./claude";
import { sendPush, type PushPayload } from "./push";

export interface JudgePayload {
  sender?: string;
  domain?: string;
  text?: string;
  url?: string;
}

export interface JudgeJob {
  familyId: string;
  source: AlertSource;
  payload: JudgePayload;
}

export interface JudgeDeps {
  judgeByRules(input: RuleInput): RuleResult;
  /** Returns null for any failure; a throw is treated the same way. */
  askClaude(env: Env, input: RuleInput, rule: RuleResult): Promise<ClaudeJudgment | null>;
  openCase(env: Env, alertId: string): Promise<unknown>;
  now(): number;
}

export const defaultJudgeDeps: JudgeDeps = {
  judgeByRules: () => {
    throw new Error("judgeByRules is not wired until #6 merges");
  },
  askClaude: (env, input, rule) => requestClaudeJudgment(env, input, rule),
  openCase: async () => {
    throw new Error("openCase is not wired until #8 merges");
  },
  now: () => Date.now(),
};

/** Queues messages can be 128 KB; the page route sends the first 5,000 characters too (task 8). */
export const JUDGE_TEXT_MAX_CHARS = 5000;
const FIELD_MAX_CHARS = 500;
export const DEDUPE_WINDOW_MS = 3600_000;
const RETRY_DELAY_SECONDS = 30;
// wrangler.jsonc sets max_retries to 3 and attempts counts from 1. A job that cannot be decided is
// settled on the third attempt, so it is never lost to running out of retries.
const LAST_ATTEMPT = 3;
/** When neither the rules nor Claude decided: kept in the app's list, no push, never called safe. */
const UNDECIDED_LEVEL: Level = 3;

const MOTHER_TITLE = "開かないで";
const CHECKING = "確かめ中";
const FALLBACK_REASON = "家族に確かめるまで待って";

const SOURCE_LABELS: Record<AlertSource, string> = {
  sms: "SMS",
  gmail: "メール",
  dns: "サイト",
  page: "ページ",
  call: "電話",
  consult: "相談",
};
const SUMMARY_EXCERPT_CHARS = 30;

function cut(text: string, max: number): string {
  const c = [...text];
  return c.length > max ? c.slice(0, max).join("") : text;
}

function optionalString(value: unknown, max: number): string | undefined | null {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== "string") return null;
  return cut(value, max);
}

function parseJob(body: unknown): JudgeJob | null {
  if (typeof body !== "object" || body === null) return null;
  const { familyId, source, payload } = body as Record<string, unknown>;
  if (typeof familyId !== "string" || familyId === "") return null;
  if (!ALERT_SOURCES.includes(source as AlertSource)) return null;
  if (typeof payload !== "object" || payload === null || Array.isArray(payload)) return null;
  const p = payload as Record<string, unknown>;
  const out: JudgePayload = {};
  for (const [key, max] of [
    ["sender", FIELD_MAX_CHARS],
    ["domain", FIELD_MAX_CHARS],
    ["url", FIELD_MAX_CHARS * 4],
    ["text", JUDGE_TEXT_MAX_CHARS],
  ] as const) {
    const value = optionalString(p[key], max);
    if (value === null) return null;
    if (value !== undefined) out[key] = value;
  }
  return { familyId, source: source as AlertSource, payload: out };
}

/** Puts a judgment job on JUDGE_QUEUE. Throws on a job of the wrong shape. */
export async function enqueueJudge(env: Env, job: JudgeJob): Promise<void> {
  const parsed = parseJob(job);
  if (!parsed) throw new Error("invalid judge job");
  await env.JUDGE_QUEUE.send(parsed);
}

function normalizeDomain(job: JudgeJob): string | null {
  let host = job.payload.domain;
  if (!host && job.payload.url) {
    try {
      host = new URL(job.payload.url).hostname;
    } catch {
      host = undefined;
    }
  }
  if (!host) return null;
  const d = host.trim().toLowerCase().replace(/\.$/, "").replace(/^www\./, "");
  return d === "" ? null : d;
}

function normalizeSender(sender: string | undefined): string | null {
  if (!sender) return null;
  const s = sender.trim().toLowerCase().replace(/[\s-]/g, "");
  return s === "" ? null : s;
}

async function keyFor(familyId: string, kind: "sender" | "domain", value: string | null): Promise<string | null> {
  if (value === null) return null;
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`${familyId}\n${kind}\n${value}`));
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}

/** What arrived, for the family's card. The sender's number is left out; the domain stays. */
function summarize(job: JudgeJob, domain: string | null): string {
  const raw = (job.payload.text ?? job.payload.url ?? "").replace(/\s+/g, " ").trim();
  const excerpt = [...raw].length > SUMMARY_EXCERPT_CHARS ? `${cut(raw, SUMMARY_EXCERPT_CHARS)}…` : raw;
  return [SOURCE_LABELS[job.source], domain ?? "", excerpt ? `「${excerpt}」` : ""].filter((s) => s !== "").join(" ");
}

interface Recipient {
  id: string;
  role: "protected" | "family";
}

type Outcome = "done" | "retry";

async function judgeOne(
  env: Env,
  message: Message<unknown>,
  budget: ExternalBudget,
  deps: JudgeDeps,
): Promise<Outcome> {
  const job = parseJob(message.body);
  if (!job) return "done";
  // The queue message id doubles as the alert id, so a redelivered message writes nothing twice.
  const alertId = message.id;
  if (await env.DB.prepare("SELECT 1 FROM alerts WHERE id = ?").bind(alertId).first()) return "done";
  // "Delete everything" may have run since the job was queued.
  if (!(await env.DB.prepare("SELECT 1 FROM families WHERE id = ?").bind(job.familyId).first())) return "done";

  const members = await env.DB.prepare(
    "SELECT id, role FROM members WHERE family_id = ? AND apns_token IS NOT NULL",
  )
    .bind(job.familyId)
    .all<Recipient>();
  // One Claude call and one push per member. A job starts only when all of it fits.
  if (budget.remaining < 1 + members.results.length) return "retry";

  const input: RuleInput = { source: job.source, ...job.payload };
  const rule = deps.judgeByRules(input);
  budget.take();
  let claude: ClaudeJudgment | null;
  try {
    claude = await deps.askClaude(env, input, rule);
  } catch {
    claude = null;
  }
  const decision = decide(rule, claude);
  if (decision.level === null && message.attempts < LAST_ATTEMPT) return "retry";
  const level: Level = decision.level ?? UNDECIDED_LEVEL;

  const now = deps.now();
  const domain = normalizeDomain(job);
  const senderKey = await keyFor(job.familyId, "sender", normalizeSender(job.payload.sender));
  const domainKey = await keyFor(job.familyId, "domain", domain);

  // Levels 1 and 2 notify; level 3 is only listed in the app (docs/design.md, データの扱い).
  let notify = level <= 2;
  if (notify && (senderKey !== null || domainKey !== null)) {
    const recent = await env.DB.prepare(
      `SELECT 1 FROM alerts WHERE family_id = ? AND notified = 1 AND created_at > ? AND level <= ?
         AND (sender_key = ? OR domain_key = ?) LIMIT 1`,
    )
      .bind(job.familyId, now - DEDUPE_WINDOW_MS, level, senderKey, domainKey)
      .first();
    if (recent) notify = false;
  }

  const summary = summarize(job, domain);
  const inserted = await env.DB.prepare(
    `INSERT INTO alerts (id, family_id, source, level, reasons, summary, rule_level, claude_level, created_at,
       sender_key, domain_key, notified)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT (id) DO NOTHING`,
  )
    .bind(
      alertId,
      job.familyId,
      job.source,
      level,
      JSON.stringify(decision.reasons),
      summary,
      decision.ruleLevel,
      decision.claudeLevel,
      now,
      senderKey,
      domainKey,
      notify ? 1 : 0,
    )
    .run();
  if (inserted.meta.changes === 0 || !notify) return "done";

  const reasons = decision.reasons;
  const data = { alertId, level, checking: decision.checking };
  const toMother: PushPayload = {
    title: MOTHER_TITLE,
    body: decision.checking ? `${reasons[0] ?? FALLBACK_REASON}\n${CHECKING}` : (reasons[0] ?? FALLBACK_REASON),
    data,
    threadId: alertId,
  };
  const toFamily: PushPayload = {
    title: summary,
    body: `${reasons.length > 0 ? reasons.join("、") : FALLBACK_REASON}${decision.checking ? `(${CHECKING})` : ""}`,
    data,
    threadId: alertId,
  };
  const ids = (role: Recipient["role"]) =>
    members.results.filter((m) => m.role === role && budget.take()).map((m) => m.id);
  await Promise.all([sendPush(env, ids("protected"), toMother), sendPush(env, ids("family"), toFamily)]);

  try {
    await deps.openCase(env, alertId);
  } catch (error) {
    // Only the error name: a message could carry the received text.
    console.error("openCase failed", error instanceof Error ? error.name : typeof error);
  }
  return "done";
}

/**
 * The JUDGE_QUEUE consumer. Jobs run one after another so that two jobs from the same sender in one
 * batch see each other for the one-an-hour rule. All jobs of a batch share one budget of outside calls.
 */
export async function handleJudgeBatch(
  batch: MessageBatch<unknown>,
  env: Env,
  deps: JudgeDeps = defaultJudgeDeps,
): Promise<void> {
  const budget = new ExternalBudget();
  for (const message of batch.messages) {
    try {
      const outcome = await judgeOne(env, message, budget, deps);
      if (outcome === "retry") message.retry({ delaySeconds: RETRY_DELAY_SECONDS });
      else message.ack();
    } catch (error) {
      console.error("judge failed", error instanceof Error ? error.name : typeof error);
      message.retry({ delaySeconds: RETRY_DELAY_SECONDS });
    }
  }
}
