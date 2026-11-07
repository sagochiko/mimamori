// The mother's voice consultation (task 12 in docs/plan.md, "スマホ相談と声" in docs/design.md).
// POST /consult takes what her iPhone transcribed and answers { reply, speak, tap?, handoff }.
//
// She is waiting with the phone in her hand. When her words tell the fake-police script (two or more
// of its parts, tellsPoliceScript), the rules alone answer at once: level 1 and the fixed line, the
// case is opened and the family told, then the answer goes back. Claude is not asked and no budget
// ticket is taken, so she does not wait, and closing the app cannot cut the request before the family
// is told. Every other consultation waits for one Claude Sonnet call in the request (the exception to
// "Queues, not the request" in .claude/rules/server.md, decided by the author on 2026-11-04). Waiting
// on fetch is not CPU time, so the 10 ms CPU limit of the free plan is not what bounds it; the 15 s
// Claude timeout is. When Claude fails or the shared budget has no ticket left, the rules alone decide
// and the answer is one of the fixed lines below.
//
// What she said is data. It goes to Claude inside <untrusted>, and nothing in it changes who is told:
// the family is told only through openCase (src/cases.ts). The notice carries the level and one line
// naming the trouble (summaryOf): a fixed line for the fake-police script, otherwise Claude's topic,
// a reason, or "スマホの相談", and never her words cut out (src/summary.ts). The card shows that line,
// the reasons, and the last answer the AI gave her (cases.ai_reply). The AI always answers her; the
// family only learns what she is troubled by, how dangerous it is, and whether it was solved.
// A later consultation that joins her open case tells the family again only when it makes the level
// heavier, or when it brings a sign of a scam to a level 2 case that had none (a consultation the AI
// did not answer is level 2 without one, #114), and sends the first notice if that one could not go
// out yet. When, after that, no family device has taken the case's notice (cases.family_notified_at
// is still NULL: no budget, APNs failed for every device, no device registered, or another caller is
// still sending it, #64), she hears NOT_REACHED in place of "家族に伝えました", so she does not think
// the family knows (#60).
//
// Her screen is a chat (#73, decided by the author on 2026-11-04), so the app may send the turns
// before this one in the same conversation (`history`, at most HISTORY_MAX_TURNS of
// HISTORY_TURN_MAX_CHARS each; the app keeps them on her iPhone, the server stores none). For words
// that only point back (pointsBack) the conversation may be older than CONVERSATION_WINDOW_MS, from
// the day before say (#118); a case is still joined only within it. They are
// data from her device, like her words: they go to Claude inside the same <untrusted> block, JSON
// encoded, and an "ai" turn is never passed as Claude's own message, so a forged answer cannot be
// read as something Claude said. The fake-police script counts her earlier words with this turn's
// (a script told in two turns is level 1), the topics the AI does not guide and the "about a
// message" check look at them too, and the family's lines must not repeat them. Who is told never
// depends on them.
//
//
// The judgment itself (the script, the call to Claude, and the decision) is in src/consult-judge.ts,
// so eval/ measures consultations on this same path (#74). This file says when Claude is asked and who
// is told.

import { requireMember, type Member } from "./auth";
import { ExternalBudget } from "./budget";
import { CaseNoticeDeferred, NOT_REACHED, openCase, recordAiReply, tellFamilyHeavier } from "./cases";
import {
  allOf,
  chars,
  type ClaudeConsult,
  type ConsultImage,
  type ConsultTurn,
  fitsUnresized,
  judgeConsult,
  type Plan,
  type RecentFinding,
  requestClaudeConsult,
  saidIn,
  TOLD_FAMILY,
} from "./consult-judge";
import { HttpError, json, readJson } from "./http";
import { judgeByRules, type RuleInput, type RuleResult } from "./rules";
import { carriesContact, repeats } from "./summary";

// What other files and the tests have imported from here before the judgment moved out.
export {
  ASK_AGAIN_REPLY,
  buildConsultRequest,
  CONSULT_MODEL,
  consultByRules,
  FALLBACK_TOPIC,
  HANDOFF_REPLY,
  judgeConsult,
  MATCH_BASIS,
  parseClaudeConsult,
  POLICE_ACTION,
  POLICE_TOPIC,
  requestClaudeConsult,
  UNANSWERED_REPLY,
  type ClaudeConsult,
  type ConsultImage,
  type ConsultImageRequest,
  type ConsultJudgment,
  type ConsultRequest,
  type ConsultRules,
  type ConsultTurn,
  type RecentFinding,
} from "./consult-judge";

export const CONSULT_TEXT_MAX_CHARS = 1000;
/** `history` in POST /consult: the app sends at most this many earlier turns of the conversation. */
export const HISTORY_MAX_TURNS = 6;
export const HISTORY_TURN_MAX_CHARS = 500;
/** A consultation that needs the family joins her open case from this recent, instead of a new one. */
export const CONVERSATION_WINDOW_MS = 60 * 60_000;

/** What the app gets ("アプリと裏側の API" in docs/plan.md). `tap` comes only with a shared image. */
export interface ConsultAnswer {
  reply: string;
  speak: string;
  tap?: { x: number; y: number };
  handoff: boolean;
}

/** On the family's card in place of an AI answer that repeats her words; she still hears the answer. */
export const AI_REPLY_ON_CARD = "答えました";

export interface ConsultDeps {
  judgeByRules(input: RuleInput): RuleResult;
  /** Returns null for any failure; a throw is treated the same way. */
  askClaude(
    env: Env,
    text: string,
    rule: RuleResult,
    history?: readonly ConsultTurn[],
    image?: ConsultImage,
    findings?: readonly RecentFinding[],
  ): Promise<ClaudeConsult | null>;
  openCase(env: Env, alertId: string, budget: ExternalBudget): Promise<unknown>;
  now(): number;
}

export const defaultConsultDeps: ConsultDeps = {
  judgeByRules,
  askClaude: (env, text, rule, history = [], image, findings = []) =>
    requestClaudeConsult(env, text, rule, history, undefined, image, findings),
  openCase,
  now: () => Date.now(),
};

/** What is read aloud: the same words, without the brackets that are only there for the eyes. */
function spoken(reply: string): string {
  return reply.replace(/[「」『』]/g, "");
}

function answer(reply: string, handoff: boolean, tap?: { x: number; y: number }): ConsultAnswer {
  return { reply, speak: spoken(reply), ...(tap ? { tap } : {}), handoff };
}

/** Claude's press point when it is on the image; a point off it would put the circle nowhere. */
function tapOn(image: ConsultImage | undefined, tap: { x: number; y: number } | undefined) {
  if (!image || !tap) return undefined;
  return tap.x < image.width && tap.y < image.height ? tap : undefined;
}

/** How far back, and how many, of what the app found are given to Claude with a consultation (#239). */
export const FINDINGS_WINDOW_MS = 7 * 24 * 3600_000;
export const FINDINGS_MAX = 3;
const DAY_MS = 24 * 3600_000;
const FOUND_SOURCES = new Set<string>(["sms", "gmail", "dns", "page"]);

/**
 * What the app found for this family lately (a mail, an SMS, a page, DNS at level 1 or 2), newest
 * first, as Claude's record for when she asks about something she received. Only what the family's
 * card has: the received text is not in D1. Reasons with a phone number or an address are left out,
 * so the scam's contact never comes back to her as the AI's words.
 */
export async function recentFindings(env: Env, familyId: string, now: number): Promise<RecentFinding[]> {
  const rows = await env.DB.prepare(
    `SELECT source, level, summary, reasons, created_at FROM alerts
      WHERE family_id = ? AND source IN ('sms', 'gmail', 'dns', 'page') AND level <= 2 AND created_at > ?
      ORDER BY created_at DESC LIMIT ${FINDINGS_MAX}`,
  )
    .bind(familyId, now - FINDINGS_WINDOW_MS)
    .all<{ source: string; level: number; summary: string | null; reasons: string | null; created_at: number }>();
  return rows.results.flatMap((r) => {
    if (!FOUND_SOURCES.has(r.source) || (r.level !== 1 && r.level !== 2)) return [];
    let reasons: unknown;
    try {
      reasons = JSON.parse(r.reasons ?? "[]");
    } catch {
      reasons = [];
    }
    return [
      {
        daysAgo: Math.max(0, Math.floor((now - r.created_at) / DAY_MS)),
        source: r.source as RecentFinding["source"],
        level: r.level,
        summary: r.summary ?? "",
        reasons: (Array.isArray(reasons) ? reasons : []).filter(
          (x): x is string => typeof x === "string" && x.trim() !== "" && !carriesContact(x),
        ),
      },
    ];
  });
}

interface OpenConsultCase {
  id: string;
  family_notified_at: number | null;
  alert_id: string;
}

/** Her most recent consultation case that is not resolved, if it is part of this conversation. */
async function openConsultCase(env: Env, familyId: string, now: number): Promise<OpenConsultCase | null> {
  return env.DB.prepare(
    `SELECT c.id, c.alert_id, c.family_notified_at
       FROM cases c JOIN alerts a ON a.id = c.alert_id
      WHERE c.family_id = ? AND a.source = 'consult' AND c.state != 'resolved' AND c.notified_at > ?
      ORDER BY c.notified_at DESC LIMIT 1`,
  )
    .bind(familyId, now - CONVERSATION_WINDOW_MS)
    .first<OpenConsultCase>();
}

async function insertAlert(env: Env, familyId: string, p: Plan, now: number): Promise<string> {
  const id = crypto.randomUUID();
  await env.DB.prepare(
    `INSERT INTO alerts (id, family_id, source, level, reasons, summary, rule_level, claude_level, created_at,
       notified, protected_notified_at)
     VALUES (?, ?, 'consult', ?, ?, ?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      id,
      familyId,
      p.level,
      JSON.stringify(p.reasons),
      p.summary,
      p.ruleLevel,
      p.claudeLevel,
      now,
      p.toFamily ? 1 : 0,
      // She has the answer on her screen; no push to her follows.
      p.toFamily ? now : null,
    )
    .run();
  return id;
}

/**
 * Opens the case and tells the family. A notice that could not go out now is retried by the tick;
 * whether it went out is read from the case afterwards (familyWasTold).
 */
async function openFor(env: Env, alertId: string, budget: ExternalBudget, deps: ConsultDeps): Promise<string | null> {
  try {
    await deps.openCase(env, alertId, budget);
  } catch (error) {
    if (!(error instanceof CaseNoticeDeferred)) throw error;
  }
  const row = await env.DB.prepare("SELECT id FROM cases WHERE alert_id = ?").bind(alertId).first<{ id: string }>();
  return row?.id ?? null;
}

/** Whether a family device took the case's notice. family_notified_at is the one record of that. */
async function familyWasTold(env: Env, caseId: string | null): Promise<boolean> {
  if (caseId === null) return false;
  const row = await env.DB.prepare("SELECT family_notified_at FROM cases WHERE id = ?")
    .bind(caseId)
    .first<{ family_notified_at: number | null }>();
  return row?.family_notified_at != null;
}

/** Her answer when the family was not told: NOT_REACHED in place of every "家族に伝えました", or after it. */
export function notReachedReply(reply: string): string {
  if (reply.includes(TOLD_FAMILY)) return reply.replaceAll(TOLD_FAMILY, NOT_REACHED);
  return `${reply.replace(/[。、\s]+$/, "")}。${NOT_REACHED}`;
}

/**
 * Answers one consultation from the protected person. `budget` is the caller's share of outside
 * calls: one ticket for Claude, then one per family device when the family is told.
 */
export async function consult(
  env: Env,
  member: Member,
  text: string,
  budget: ExternalBudget,
  deps: ConsultDeps = defaultConsultDeps,
  history: readonly ConsultTurn[] = [],
  image?: ConsultImage,
): Promise<ConsultAnswer> {
  const now = deps.now();
  const open = await openConsultCase(env, member.familyId, now);

  // The main scene answers at once: she does not wait, and the family is told before she can close
  // the app and cut the request. No ticket is taken for Claude (judgeConsult asks only off the script).
  const p = await judgeConsult(
    text,
    history,
    async (rule, turns) => {
      if (!budget.take()) return null;
      // A record that cannot be read must not cost her the answer: Claude is asked without it.
      const findings = await recentFindings(env, member.familyId, now).catch(() => []);
      try {
        return await deps.askClaude(env, text, rule, turns, image, findings);
      } catch {
        return null;
      }
    },
    deps.judgeByRules,
    image !== undefined,
  );
  const said = saidIn(text, history);
  if (!p.record) return answer(p.reply, false, tapOn(image, p.tap));

  let caseId: string | null = null;
  if (p.toFamily && open) {
    // Same conversation: her open case gets the heavier level and its line. The family hears again
    // only when it became heavier; a first notice still waiting goes out now, with the level as it is.
    // A sign of a scam at level 2 counts as heavier on a level 2 case that had no sign, so the family
    // learns of the fake police after a question the AI could not answer (#114). Whether the case had
    // one is read from what was judged: a case opened without a sign has Claude's level 3, or no
    // level from Claude or the rules (Plan.sign). The judged levels move with the line, so the next
    // sign at level 2 is no heavier.
    const heavier = await env.DB.prepare(
      `UPDATE alerts SET level = ?, reasons = ?, summary = ?, rule_level = ?, claude_level = ?
        WHERE id = ? AND (level > ? OR (? = 1 AND level = 2 AND COALESCE(claude_level, rule_level, 3) = 3))`,
    )
      .bind(
        p.level,
        JSON.stringify(p.reasons),
        p.summary,
        p.ruleLevel,
        p.claudeLevel,
        open.alert_id,
        p.level,
        p.sign && p.level === 2 ? 1 : 0,
      )
      .run();
    caseId = open.id;
    if (open.family_notified_at === null) await openFor(env, open.alert_id, budget, deps);
    else if (heavier.meta.changes === 1) await tellFamilyHeavier(env, open.id, budget);
  } else {
    const alertId = await insertAlert(env, member.familyId, p, now);
    if (p.toFamily) caseId = await openFor(env, alertId, budget, deps);
  }
  const reply = p.toFamily && !(await familyWasTold(env, caseId)) ? notReachedReply(p.reply) : p.reply;
  // She hears the whole answer; the card gets a fixed line instead when the answer repeats her words.
  if (caseId !== null) await recordAiReply(env, caseId, repeats(reply, allOf(said)) ? AI_REPLY_ON_CARD : reply);
  return answer(reply, p.toFamily, tapOn(image, p.tap));
}

/**
 * `history` as docs/plan.md fixes it: absent, or at most HISTORY_MAX_TURNS turns of { role, text },
 * role "protected" or "ai", text of 1 to HISTORY_TURN_MAX_CHARS characters. Anything else is a 400.
 */
export function parseHistory(value: unknown): ConsultTurn[] {
  if (value === undefined) return [];
  const invalid = new HttpError(400, "consult_history_invalid");
  if (!Array.isArray(value) || value.length > HISTORY_MAX_TURNS) throw invalid;
  return value.map((item: unknown) => {
    if (typeof item !== "object" || item === null || Array.isArray(item)) throw invalid;
    const { role, text } = item as Record<string, unknown>;
    if (role !== "protected" && role !== "ai") throw invalid;
    if (typeof text !== "string" || text.trim() === "" || chars(text) > HISTORY_TURN_MAX_CHARS) throw invalid;
    return { role, text: text.trim() };
  });
}

/**
 * The most base64 an image may carry: about 2.2 MB of file. A 1179x2556 screenshot as the app sends
 * it (JPEG) is well under it; the cap keeps parsing the body inside the free plan's CPU time.
 */
export const IMAGE_MAX_BASE64_CHARS = 3_000_000;
const BASE64 = /^[A-Za-z0-9+/]+={0,2}$/;
/**
 * Only this much of each end of `data` is checked: the whole of it took about 9.5 ms on Node for 3
 * million characters (review 1 of PR #186), the free plan's whole CPU time. Broken base64 in between
 * is refused by Claude with a 400, which is an answer the AI could not give.
 */
const BASE64_CHECKED_CHARS = 256;

/**
 * `image` as POST /consult takes it: absent, or { mediaType, data, width, height } with a JPEG or PNG
 * in base64 whose size Claude reads unresized (fitsUnresized), so its press points need no mapping on
 * the server. Anything else is a 400, more data than IMAGE_MAX_BASE64_CHARS a 413.
 */
export function parseImage(value: unknown): ConsultImage | undefined {
  if (value === undefined) return undefined;
  const invalid = new HttpError(400, "consult_image_invalid");
  if (typeof value !== "object" || value === null || Array.isArray(value)) throw invalid;
  const { mediaType, data, width, height } = value as Record<string, unknown>;
  if (mediaType !== "image/jpeg" && mediaType !== "image/png") throw invalid;
  if (typeof data !== "string" || data === "") throw invalid;
  if (data.length > IMAGE_MAX_BASE64_CHARS) throw new HttpError(413, "consult_image_too_large");
  const ends = [data.slice(0, BASE64_CHECKED_CHARS), data.slice(-BASE64_CHECKED_CHARS)];
  if (data.length % 4 !== 0 || !ends.every((e) => BASE64.test(e))) throw invalid;
  if (!Number.isInteger(width) || !Number.isInteger(height)) throw invalid;
  const w = width as number;
  const h = height as number;
  if (w < 1 || h < 1 || !fitsUnresized(w, h)) throw invalid;
  return { mediaType, data, width: w, height: h };
}

/**
 * POST /consult with { text, history?, image? }: only the protected person consults. With an image,
 * her words may be left out; without one they are required. The image is passed to Claude and kept
 * nowhere (docs/design.md: スクショはその場で処理して残さない).
 */
export async function consultRoute(request: Request, env: Env): Promise<Response> {
  const me = await requireMember(request, env);
  if (me.role !== "protected") throw new HttpError(403, "protected_only");
  const { text, history, image: rawImage } = await readJson(request);
  const image = parseImage(rawImage);
  if (text !== undefined && typeof text !== "string") throw new HttpError(400, "consult_text_invalid");
  const trimmed = (text ?? "").trim();
  if ((trimmed === "" && image === undefined) || chars(trimmed) > CONSULT_TEXT_MAX_CHARS) {
    throw new HttpError(400, "consult_text_invalid");
  }
  return json(await consult(env, me, trimmed, new ExternalBudget(), defaultConsultDeps, parseHistory(history), image));
}
