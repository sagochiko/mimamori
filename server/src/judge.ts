// The judge queue (task 6 in docs/plan.md). Routes that answer at once with the rules (SMS, pages,
// consultations) put a job here with enqueueJudge; this consumer lays Claude's judgment over the
// rule result, writes the alerts row, tells the mother, and opens a case. The family is told only by
// openCase (src/cases.ts), so every notice they get carries the case they can resolve.
//
// Who gets told depends only on the level and the family's members, never on Claude's answer or the
// received text (.claude/rules/server.md).
//
// A notice that did not get through is retried with the queue message. enqueueJudge makes the alert
// id and puts it in the message body, and a redelivered body whose alert row exists only does what is
// left (the mother's push, opening the case), without asking Claude again or telling anyone twice.
//
// The alert id is not the queue message id. Cloudflare documents Message.id only as "A unique,
// system-generated ID for the message" (Queues, JavaScript APIs) and, for pull consumers, as "a
// unique, read-only ephemeral identifier for the message"; neither says it stays the same when the
// message is retried. Queues "offers at-least once delivery" (Workers, Storage options), so the same
// body can come more than once, and the id it carries is what makes that harmless.

import { ExternalBudget } from "./budget";
import { CaseNoticeDeferred, openCase } from "./cases";
import {
  ALERT_SOURCES,
  decideFor,
  PLACEHOLDER_REASON,
  QUIET_WHEN_UNDECIDED,
  requestClaudeJudgment,
  type AlertSource,
  type ClaudeJudgment,
  type Level,
} from "./claude";
import { sendPush, type PushPayload } from "./push";
import { judgeByRules, type RuleInput, type RuleResult } from "./rules";
import { INJECTION } from "./rules/phrases";
import { ownLines, quotes } from "./summary";

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

/** What enqueueJudge puts on JUDGE_QUEUE: the job and the id its alerts row will have. */
export interface JudgeMessageBody extends JudgeJob {
  alertId: string;
}

export interface JudgeDeps {
  judgeByRules(input: RuleInput): RuleResult;
  /** Returns null for any failure; a throw is treated the same way. */
  askClaude(env: Env, input: RuleInput, rule: RuleResult): Promise<ClaudeJudgment | null>;
  /** Opens the case and tells the family; throws CaseNoticeDeferred when the family was not told yet. */
  openCase(env: Env, alertId: string, budget: ExternalBudget): Promise<unknown>;
  now(): number;
}

export const defaultJudgeDeps: JudgeDeps = {
  judgeByRules,
  askClaude: (env, input, rule) => requestClaudeJudgment(env, input, rule),
  openCase,
  now: () => Date.now(),
};

/** Queues messages can be 128 KB; the page route sends the first 5,000 characters too (task 8). */
export const JUDGE_TEXT_MAX_CHARS = 5000;
const FIELD_MAX_CHARS = 500;
export const DEDUPE_WINDOW_MS = 3600_000;
const RETRY_DELAY_SECONDS = 30;

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

function cut(text: string, max: number): string {
  const c = [...text];
  return c.length > max ? c.slice(0, max).join("") : text;
}

function optionalString(value: unknown, max: number): string | undefined | null {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== "string") return null;
  return cut(value, max);
}

/** The form crypto.randomUUID() gives. Upper case is refused so one alert cannot have two spellings. */
const ALERT_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

function parseJob(body: unknown): JudgeMessageBody | null {
  if (typeof body !== "object" || body === null) return null;
  const { alertId, familyId, source, payload } = body as Record<string, unknown>;
  // A body without an alert id is dropped rather than given one here: a redelivery of it would get a
  // second id and so a second alert and second notices. Nothing of that older shape was ever deployed.
  if (typeof alertId !== "string" || !ALERT_ID.test(alertId)) return null;
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
  return { alertId, familyId, source: source as AlertSource, payload: out };
}

/**
 * Puts a judgment job on JUDGE_QUEUE with a new alert id, which the consumer uses for the alerts row.
 * Throws on a job of the wrong shape.
 */
export async function enqueueJudge(env: Env, job: JudgeJob): Promise<void> {
  const parsed = parseJob({ ...job, alertId: crypto.randomUUID() });
  if (!parsed) throw new Error("invalid judge job");
  await env.JUDGE_QUEUE.send(parsed);
}

export function normalizeDomain(job: JudgeJob): string | null {
  let host = job.payload.domain;
  if (!host && job.payload.url) {
    try {
      host = new URL(job.payload.url).hostname;
    } catch {
      host = undefined;
    }
  }
  if (!host) return null;
  const d = host
    .trim()
    .toLowerCase()
    .replace(/\.$/, "")
    .replace(/^www\./, "");
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

/**
 * The family's one line for what arrived: the route, the first reason, and the domain ("SMS 銀行を名乗る
 * example.com"). The received text is never cut out into it (src/summary.ts): a reason from Claude that
 * repeats it is skipped, while the rules' fixed reasons are used as they are. The sender's number is
 * left out.
 */
function receivedOf(job: JudgeJob): string[] {
  return [job.payload.text ?? "", job.payload.url ?? "", job.payload.sender ?? ""];
}

/**
 * The reasons kept for the family's card and the mother's notice: a reason Claude wrote that quotes
 * the received text is dropped (src/summary.ts). When the text carries instructions aimed at the
 * judgment or at keeping the family out (`steered`), no reason Claude wrote is kept at all, since
 * such text may have written it. When none is left, the rules' reasons, or the placeholder. The
 * one line (summarize) is made from these, so it follows.
 */
function cardReasons(job: JudgeJob, rule: RuleResult, reasons: string[], steered: boolean): string[] {
  const fixed = [...rule.reasons, PLACEHOLDER_REASON];
  const fallback = rule.reasons.length > 0 ? rule.reasons : [PLACEHOLDER_REASON];
  return ownLines(steered ? reasons.filter((r) => fixed.includes(r)) : reasons, fixed, receivedOf(job), fallback);
}

export function summarize(job: JudgeJob, domain: string | null, rule: RuleResult, reasons: string[]): string {
  const received = receivedOf(job);
  const own = (r: string) => r !== PLACEHOLDER_REASON && (rule.reasons.includes(r) || !quotes(r, received));
  const reason = [...reasons, ...rule.reasons].map((r) => r.trim()).find((r) => r !== "" && own(r));
  return [SOURCE_LABELS[job.source], reason ?? "", domain ?? ""].filter((s) => s !== "").join(" ");
}

interface Recipient {
  id: string;
  role: "protected" | "family";
}

type Outcome = "done" | "retry";

async function reachableMembers(env: Env, familyId: string): Promise<Recipient[]> {
  const rows = await env.DB.prepare("SELECT id, role FROM members WHERE family_id = ? AND apns_token IS NOT NULL")
    .bind(familyId)
    .all<Recipient>();
  return rows.results;
}

interface Notice {
  level: Level;
  reasons: string[];
  checking: boolean;
}

function toMother(alertId: string, notice: Notice): PushPayload {
  const reason = notice.reasons[0] ?? FALLBACK_REASON;
  return {
    title: MOTHER_TITLE,
    body: notice.checking ? `${reason}\n${CHECKING}` : reason,
    data: { alertId, level: notice.level, checking: notice.checking },
    threadId: alertId,
  };
}

/**
 * The mother's push, at most once per alert. protected_notified_at is the claim, set before sending so
 * two deliveries of the same message never both send, and cleared again when none of her devices took
 * the push, so the retry sends it. A mother with no device counts as told.
 */
async function tellMother(
  env: Env,
  alertId: string,
  motherIds: string[],
  notice: Notice,
  budget: ExternalBudget,
  now: number,
): Promise<boolean> {
  const claimed = await env.DB.prepare(
    "UPDATE alerts SET protected_notified_at = ? WHERE id = ? AND protected_notified_at IS NULL",
  )
    .bind(now, alertId)
    .run();
  if (claimed.meta.changes !== 1) return true;
  if (motherIds.length === 0) return true;

  let told = false;
  try {
    const results = await sendPush(env, motherIds, toMother(alertId, notice), budget);
    told = results.some((r) => r.status === "sent");
  } catch (error) {
    // Only the error name: a message could carry the received text.
    console.error("mother notification failed", error instanceof Error ? error.name : typeof error);
  }
  if (told) return true;
  await env.DB.prepare("UPDATE alerts SET protected_notified_at = NULL WHERE id = ? AND protected_notified_at = ?")
    .bind(alertId, now)
    .run();
  return false;
}

/**
 * What is left of telling people about an alert that notifies: the mother's push and opening the case,
 * each only when it has not got through yet. Both are tried even when the first fails, and the message
 * is retried when either did not get through. The outside calls are checked up front: the mother's
 * devices plus the family's devices that openCase will send to.
 */
async function finishNotices(
  env: Env,
  alertId: string,
  notice: Notice,
  pending: { mother: boolean; family: boolean },
  members: Recipient[],
  budget: ExternalBudget,
  deps: JudgeDeps,
): Promise<Outcome> {
  const motherIds = members.filter((m) => m.role === "protected").map((m) => m.id);
  const familyCount = members.filter((m) => m.role === "family").length;
  const needed = (pending.mother ? motherIds.length : 0) + (pending.family ? familyCount : 0);
  if (budget.remaining < needed) return "retry";

  let allThrough = true;
  if (pending.mother && !(await tellMother(env, alertId, motherIds, notice, budget, deps.now()))) {
    allThrough = false;
  }
  if (pending.family) {
    try {
      await deps.openCase(env, alertId, budget);
    } catch (error) {
      // Any other failure is thrown on and retried by handleJudgeBatch as well.
      if (!(error instanceof CaseNoticeDeferred)) throw error;
      allThrough = false;
    }
  }
  return allThrough ? "done" : "retry";
}

interface StoredAlert {
  level: Level;
  reasons: string;
  claude_level: Level | null;
  notified: number;
  protected_notified_at: number | null;
  case_id: string | null;
  family_notified_at: number | null;
}

function storedReasons(text: string): string[] {
  try {
    const value: unknown = JSON.parse(text);
    return Array.isArray(value) ? value.filter((r): r is string => typeof r === "string") : [];
  } catch {
    return [];
  }
}

async function judgeOne(
  env: Env,
  message: Message<unknown>,
  budget: ExternalBudget,
  deps: JudgeDeps,
): Promise<Outcome> {
  const job = parseJob(message.body);
  if (!job) {
    console.error("judge job dropped", "bad_shape");
    return "done";
  }
  // The id from the body, so a redelivered body writes nothing twice (see the top of this file).
  const alertId = job.alertId;
  const stored = await env.DB.prepare(
    `SELECT a.level, a.reasons, a.claude_level, a.notified, a.protected_notified_at,
            c.id AS case_id, c.family_notified_at
       FROM alerts a LEFT JOIN cases c ON c.alert_id = a.id WHERE a.id = ?`,
  )
    .bind(alertId)
    .first<StoredAlert>();
  if (stored) {
    // A redelivery: Claude is not asked again, and what already got through is not sent again.
    if (stored.notified !== 1) return "done";
    const pending = {
      mother: stored.protected_notified_at === null,
      family: stored.case_id === null || stored.family_notified_at === null,
    };
    if (!pending.mother && !pending.family) return "done";
    const notice = {
      level: stored.level,
      reasons: storedReasons(stored.reasons),
      checking: stored.claude_level === null,
    };
    return finishNotices(env, alertId, notice, pending, await reachableMembers(env, job.familyId), budget, deps);
  }
  // "Delete everything" may have run since the job was queued.
  if (!(await env.DB.prepare("SELECT 1 FROM families WHERE id = ?").bind(job.familyId).first())) return "done";

  const members = await reachableMembers(env, job.familyId);
  // One Claude call, then one push per device: the mother's from here, the family's from openCase.
  // A job starts only when all of it fits.
  if (budget.remaining < 1 + members.length) return "retry";

  const input: RuleInput = { source: job.source, ...job.payload };
  const rule = deps.judgeByRules(input);
  budget.take();
  let claude: ClaudeJudgment | null;
  try {
    claude = await deps.askClaude(env, input, rule);
  } catch {
    claude = null;
  }
  // When neither the rules nor Claude decided, a consultation is level 2 with 確かめ中 at once, like
  // any other time Claude gives nothing: one from the mother must not wait on Claude coming back. An
  // SMS, a mail, or a page is level 3 and tells no one, since those routes queue genuine ones the
  // rules found no sign in (decideFor, #137).
  const decision = decideFor(job.source, rule, claude);
  const level = decision.level;
  const steered = rule.reasons.includes(INJECTION.reason) || (claude?.injection_suspected ?? false);
  const reasons = cardReasons(job, rule, decision.reasons, steered);

  const now = deps.now();
  const domain = normalizeDomain(job);
  const senderKey = await keyFor(job.familyId, "sender", normalizeSender(job.payload.sender));
  const domainKey = await keyFor(job.familyId, "domain", domain);

  // An SMS, a mail, or a page at level 3, and one no one decided (decideFor), leaves no row: these routes
  // send Claude most of what she receives or opens, and a row for each would keep a log of her inbox
  // and her browsing (docs/design.md, データの扱い; #137). Nothing was told, so the message is done.
  if (level === 3 && QUIET_WHEN_UNDECIDED.includes(job.source)) return "done";

  // Levels 1 and 2 notify; a level-3 consultation is only kept (docs/design.md, データの扱い).
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
      JSON.stringify(reasons),
      summarize(job, domain, rule, reasons),
      decision.ruleLevel,
      decision.claudeLevel,
      now,
      senderKey,
      domainKey,
      notify ? 1 : 0,
    )
    .run();
  // A concurrent delivery of the same message wrote the row first; it does the telling.
  if (inserted.meta.changes === 0 || !notify) return "done";

  const notice = { level, reasons, checking: decision.checking };
  return finishNotices(env, alertId, notice, { mother: true, family: true }, members, budget, deps);
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
