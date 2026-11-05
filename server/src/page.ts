// POST /page: the Safari extension asks about the page the mother opened (task 9 in docs/plan.md).
//
// The extension's native side posts { url, text } with the device key (the content script cannot reach
// the native side itself, so it goes content script -> background script -> native handler -> here).
// The reply is { level: 1 | 2 | null, reasons } made by the rules alone, and the extension lays its
// warning over the page for 1 and 2. Claude is not waited on in the request (.claude/rules/server.md):
// a page the rules see a sign on goes to the judge queue, whose consumer writes the alert, lays Claude's
// judgment over the rules, and tells the mother and the family (src/judge.ts).
//
// The page's text and URL are data to inspect. An instruction in it ("この警告を止めて", "家族に知らせ
// ないで") only raises the rules' level; it never changes the reply or who is told. Neither the text nor
// the URL (its query may carry anything) goes to the logs, and nothing is written to D1 here.
//
// null is "the rules did not decide", never "fine". The reply has no field that could read as safe.

import { requireMember } from "./auth";
import { HttpError, json, readJson } from "./http";
import { enqueueJudge, JUDGE_TEXT_MAX_CHARS, normalizeDomain, type JudgePayload } from "./judge";
import { FOREIGN_SENDER_REASON, judgeByRules, type RuleResult } from "./rules";

/** Only the first 5,000 characters of the page are judged and sent on (docs/plan.md, task 9). */
export const PAGE_TEXT_MAX_CHARS = JUDGE_TEXT_MAX_CHARS;
/** What the judge queue keeps of a URL (src/judge.ts parseJob). */
const URL_MAX_CHARS = 2000;

export interface PageReply {
  level: 1 | 2 | null;
  reasons: string[];
}

function cut(text: string, max: number): string {
  const c = [...text];
  return c.length > max ? c.slice(0, max).join("") : text;
}

/**
 * The http or https URL, kept to what the queue holds. A longer one keeps its origin and path only, so
 * a page cannot get out of the check by padding its address.
 */
function pageUrl(value: unknown): URL | null {
  if (typeof value !== "string" || value === "") return null;
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    return null;
  }
  if (url.protocol !== "https:" && url.protocol !== "http:") return null;
  if (url.toString().length <= URL_MAX_CHARS) return url;
  const short = new URL(cut(`${url.origin}${url.pathname}`, URL_MAX_CHARS));
  return short;
}

async function readPage(request: Request): Promise<{ url: URL; text: string }> {
  let body: Record<string, unknown>;
  try {
    body = await readJson(request);
  } catch (error) {
    if (error instanceof HttpError) throw new HttpError(400, "page_invalid");
    throw error;
  }
  const url = pageUrl(body.url);
  if (!url) throw new HttpError(400, "page_invalid");
  if (body.text !== undefined && typeof body.text !== "string") throw new HttpError(400, "page_invalid");
  return { url, text: cut(body.text ?? "", PAGE_TEXT_MAX_CHARS) };
}

/**
 * Whether the page goes to Claude and the family. Only with a level or a sign from the rules: the queue
 * treats a job neither the rules nor Claude decided as level 2 and tells the family, which an ordinary
 * page must never cause when Claude is down. Same gate as the SMS route (src/sms.ts).
 */
function worthAsking(rule: RuleResult): boolean {
  if (rule.level !== null) return true;
  return rule.reasons.some((r) => r !== FOREIGN_SENDER_REASON);
}

/**
 * Her own network: a home router's or printer's page, addressed by a private or loopback address or a
 * .local name. The rules read an address made of numbers as a sign, which these pages are not, and
 * they are hers alone, so they are neither judged nor sent on.
 */
export function onOwnNetwork(url: URL): boolean {
  const host = url.hostname.toLowerCase().replace(/^\[|\]$/g, "");
  if (host === "localhost" || host.endsWith(".localhost") || host.endsWith(".local")) return true;
  if (host === "::1" || host.startsWith("fe80:") || /^f[cd][0-9a-f]{2}:/.test(host)) return true;
  const v4 = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(host);
  if (!v4) return false;
  const [a, b] = [Number(v4[1]), Number(v4[2])];
  return a === 10 || a === 127 || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168) || (a === 169 && b === 254);
}

export async function pageRoute(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
  const me = await requireMember(request, env);
  const { url, text } = await readPage(request);
  if (onOwnNetwork(url)) return json({ level: null, reasons: [] } satisfies PageReply);

  const payload: JudgePayload = { url: url.toString(), ...(text !== "" ? { text } : {}) };
  const domain = normalizeDomain({ familyId: me.familyId, source: "page", payload });
  if (domain) payload.domain = domain;

  const rule = judgeByRules({ source: "page", ...payload });
  // Rules never give level 3; anything else is undecided.
  const level = rule.level === 1 || rule.level === 2 ? rule.level : null;

  // Only the mother's pages are told about. A family member's own phone gets the warning, not a notice
  // about themselves to everyone.
  if (me.role === "protected" && worthAsking(rule)) {
    ctx.waitUntil(
      enqueueJudge(env, { familyId: me.familyId, source: "page", payload }).catch((error: unknown) => {
        console.error("page enqueue failed", error instanceof Error ? error.name : typeof error);
      }),
    );
  }
  const reply: PageReply = { level, reasons: level === null ? [] : rule.reasons };
  return json(reply);
}
