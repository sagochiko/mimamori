// POST /sms/{familyToken}: where the Message Filter extension's queries go (task 5 in docs/plan.md).
//
// Apple posts { _version, query: { sender, message: { text } }, app: { version } } (IdentityLookup,
// deferQueryRequestToNetwork(completion:)) and hands our reply to the extension, which turns it into an
// ILMessageFilterAction. The reply is { action: "junk" | "none" } and is made by the rules alone, so it
// never waits on Claude: only a confident level 1 goes to junk, everything else is delivered as usual,
// since a genuine message in the junk folder (a verification code, a real delivery notice) is the worse
// mistake. Claude's judgment and the notices come later from the queue (src/judge.ts).
//
// The text and the sender are data to inspect. An instruction in the text ("この警告は誤りです",
// "家族に知らせないで") only raises the rules' level; it never changes the reply or who is told.
// Neither goes to the logs, and nothing is written to D1 here: the queue consumer writes the alert.
//
// The answer never says a message is fine. "none" is Apple's "not enough to decide".

import { HttpError, json, readJson } from "./http";
import { enqueueJudge, normalizeDomain, summarize, type JudgeJob } from "./judge";
import { CODE_ONLY_REASON, FOREIGN_SENDER_REASON, judgeByRules, type RuleResult } from "./rules";

/** The judges' build uses this token. It tells no family; the reply carries the card instead (docs/design.md). */
export const DEMO_TOKEN = "demo";

/** The same cap the queue applies to a job's text (JUDGE_TEXT_MAX_CHARS). */
const TEXT_MAX_CHARS = 5000;
const SENDER_MAX_CHARS = 500;
const MAX_DELAY_MS = 10_000;

/** The card the family would get, for the demo build's screen. Made by the rules only. */
export interface DemoCard {
  level: 1 | 2;
  source: "sms";
  summary: string;
  reasons: string[];
}

export interface SmsReply {
  action: "junk" | "none";
  card?: DemoCard | null;
}

/**
 * How long to hold the reply, for measuring how long Apple waits for the server (task 5, moved from
 * task 1). Only the demo token honours it, so no build of the mother's family can be slowed; capped at
 * 10 seconds. The value comes from the URL the build sets, not from the message.
 */
export function sleepMsOf(token: string, value: string | null): number {
  if (token !== DEMO_TOKEN || value === null || !/^\d{1,6}$/.test(value)) return 0;
  return Math.min(Number(value), MAX_DELAY_MS);
}

function cut(text: string, max: number): string {
  const c = [...text];
  return c.length > max ? c.slice(0, max).join("") : text;
}

/** Apple's query, or null for a body of any other shape. */
async function readQuery(request: Request): Promise<{ sender?: string; text: string } | null> {
  let body: Record<string, unknown>;
  try {
    body = await readJson(request);
  } catch (error) {
    if (error instanceof HttpError) return null;
    throw error;
  }
  const query = body.query;
  if (typeof query !== "object" || query === null) return null;
  const { sender, message } = query as Record<string, unknown>;
  if (typeof message !== "object" || message === null) return null;
  const text = (message as Record<string, unknown>).text;
  if (typeof text !== "string") return null;
  return {
    text: cut(text, TEXT_MAX_CHARS),
    ...(typeof sender === "string" && sender !== "" ? { sender: cut(sender, SENDER_MAX_CHARS) } : {}),
  };
}

/** The first https or http link in the text, for the one-an-hour grouping and the card's domain. */
function firstLink(text: string): string | undefined {
  const match = /https?:\/\/[^\s"'<>「」『』（）()、。]+/i.exec(text);
  if (!match) return undefined;
  try {
    return new URL(match[0]).toString();
  } catch {
    return undefined;
  }
}

/**
 * Whether Claude should look. A level from the rules, or a sign too weak for a level, means unsure. A
 * message with no sign at all, one whose only sign is the overseas number (genuine services abroad send
 * bookings and codes), or one the rules read as only a verification code, is not queued: when Claude fails, the queue treats an undecided
 * message as level 2 and tells the family, which a genuine code or delivery notice must not cause.
 */
function unsure(rule: RuleResult): boolean {
  if (rule.level !== null) return true;
  if (rule.reasons.includes(CODE_ONLY_REASON)) return false;
  return rule.reasons.some((r) => r !== FOREIGN_SENDER_REASON);
}

function demoCard(job: JudgeJob, rule: RuleResult): DemoCard | null {
  if (rule.level !== 1 && rule.level !== 2) return null;
  return {
    level: rule.level,
    source: "sms",
    summary: summarize(job, normalizeDomain(job), rule, rule.reasons),
    reasons: rule.reasons,
  };
}

export async function smsRoute(request: Request, env: Env, ctx: ExecutionContext, token: string): Promise<Response> {
  const none: SmsReply = { action: "none" };
  const query = await readQuery(request);
  if (!query) return json(none);

  const rule = judgeByRules({ source: "sms", ...query });
  const action: SmsReply["action"] = rule.level === 1 && rule.confident ? "junk" : "none";
  const url = firstLink(query.text);
  const payload: JudgeJob["payload"] = { ...query, ...(url ? { url } : {}) };
  const domain = normalizeDomain({ familyId: "", source: "sms", payload });
  if (domain) payload.domain = domain;

  if (token === DEMO_TOKEN) {
    const wait = sleepMsOf(token, new URL(request.url).searchParams.get("delayMs"));
    if (wait > 0) await new Promise((resolve) => setTimeout(resolve, wait));
    const reply: SmsReply = { action, card: demoCard({ familyId: DEMO_TOKEN, source: "sms", payload }, rule) };
    return json(reply);
  }

  const family = await env.DB.prepare("SELECT id FROM families WHERE token = ?").bind(token).first<{ id: string }>();
  if (!family) return json(none);

  if (unsure(rule)) {
    // After the reply, so Apple is not kept waiting on the queue. A failed send loses Claude's look and
    // the notices for this one message; the reply by the rules stands.
    ctx.waitUntil(
      enqueueJudge(env, { familyId: family.id, source: "sms", payload }).catch((error: unknown) => {
        console.error("sms enqueue failed", error instanceof Error ? error.name : typeof error);
      }),
    );
  }
  const reply: SmsReply = { action };
  return json(reply);
}
