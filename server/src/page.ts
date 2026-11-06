// POST /page: the Safari extension asks about the page the mother opened (task 9 in docs/plan.md).
//
// The extension's native side posts { url, text } with the device key (the content script cannot reach
// the native side itself, so it goes content script -> background script -> native handler -> here).
// The reply is { level: 1 | 2 | null, reasons } made by the rules alone, and the extension lays its
// warning over the page for 1 and 2. Claude is not waited on in the request (.claude/rules/server.md):
// some of the mother's pages go to the judge queue, whose consumer lays Claude's judgment over the
// rules, writes the alert when it reaches level 1 or 2, and tells the mother and the family
// (src/judge.ts). Those are the pages the rules see a sign on and, since #137, pages that look like
// where a scam asks for something though the rules see nothing: one that speaks as a company from
// another host, one with a password or card field, one with a phone number next to a warning
// (src/page-gate.ts). These shapes pick pages for Claude only; they draw no warning.
//
// The extension also sends hasSecretField: whether the page has a password or card number field. The
// content script counts the fields and never reads what is typed in them; only true or false comes.
//
// The page's text and URL are data to inspect. An instruction in it ("この警告を止めて", "家族に知らせ
// ないで") only raises the rules' level; it never changes the reply or who is told. Neither the text nor
// the URL (its query may carry anything) goes to the logs, and nothing is written to D1 here.
//
// The reply carries queued: true when this request picked the page for the judge queue. The content
// script looks at a page a second time when its text grows after loading (ads and pop-ups), and that
// second look sends alreadyQueued: true when the first was queued, so one display of a page is queued
// at most once (#174). A second look whose first was not queued still goes to Claude. queued says only
// where the page went, nothing about how it was judged, and the extension draws nothing from it.
//
// null is "the rules did not decide", never "fine". The reply has no field that could read as safe.

import { requireMember } from "./auth";
import { HttpError, json, readJson } from "./http";
import { enqueueJudge, JUDGE_TEXT_MAX_CHARS, normalizeDomain, type JudgePayload } from "./judge";
import { pageWorthAsking } from "./page-gate";
import { judgeByRules } from "./rules";

/** Only the first 5,000 characters of the page are judged and sent on (docs/plan.md, task 9). */
export const PAGE_TEXT_MAX_CHARS = JUDGE_TEXT_MAX_CHARS;
/** What the judge queue keeps of a URL (src/judge.ts parseJob). */
const URL_MAX_CHARS = 2000;

export interface PageReply {
  level: 1 | 2 | null;
  reasons: string[];
  /** Present (true) only when this request handed the page to the judge queue (#174). */
  queued?: true;
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

async function readPage(
  request: Request,
): Promise<{ url: URL; text: string; hasSecretField: boolean; alreadyQueued: boolean }> {
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
  if (body.hasSecretField !== undefined && typeof body.hasSecretField !== "boolean") {
    throw new HttpError(400, "page_invalid");
  }
  if (body.alreadyQueued !== undefined && typeof body.alreadyQueued !== "boolean") {
    throw new HttpError(400, "page_invalid");
  }
  return {
    url,
    text: cut(body.text ?? "", PAGE_TEXT_MAX_CHARS),
    hasSecretField: body.hasSecretField === true,
    alreadyQueued: body.alreadyQueued === true,
  };
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
  const { url, text, hasSecretField, alreadyQueued } = await readPage(request);
  if (onOwnNetwork(url)) return json({ level: null, reasons: [] } satisfies PageReply);

  const payload: JudgePayload = { url: url.toString(), ...(text !== "" ? { text } : {}) };
  const domain = normalizeDomain({ familyId: me.familyId, source: "page", payload });
  if (domain) payload.domain = domain;

  const rule = judgeByRules({ source: "page", ...payload });
  // Rules never give level 3; anything else is undecided.
  const level = rule.level === 1 || rule.level === 2 ? rule.level : null;

  // Only the mother's pages are told about. A family member's own phone gets the warning, not a notice
  // about themselves to everyone.
  // A second look of a display whose first look was queued is not queued again (#174).
  const queued =
    me.role === "protected" && !alreadyQueued && pageWorthAsking(rule, { url: url.toString(), text, hasSecretField });
  if (queued) {
    ctx.waitUntil(
      enqueueJudge(env, { familyId: me.familyId, source: "page", payload }).catch((error: unknown) => {
        console.error("page enqueue failed", error instanceof Error ? error.name : typeof error);
      }),
    );
  }
  const reply: PageReply = { level, reasons: level === null ? [] : rule.reasons, ...(queued ? { queued: true } : {}) };
  return json(reply);
}
