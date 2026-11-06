// Gmail (task 7 in docs/plan.md): the protected member's grant, the 5-minute watch over her inbox,
// and taking the grant back for "delete everything".
//
// Google's shapes, checked 2026-11-05 on its reference pages:
// - OAuth for web server apps: https://developers.google.com/identity/protocols/oauth2/web-server
//   (auth URL and its parameters, the code exchange and refresh at the token endpoint, invalid_grant
//   for a refresh token that expired or was revoked, the revoke endpoint). "access_type=offline"
//   returns a refresh token only on the first exchange unless consent is asked again, so every grant
//   asks with "prompt=consent".
// - A Testing app's refresh tokens expire in 7 days: https://developers.google.com/identity/protocols/oauth2
// - users.history.list: https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.history/list
//   ("Returns history records after the specified startHistoryId"; an out-of-date start "typically
//   returns an HTTP 404").
// - users.messages.get with format=full: https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.messages/get
//   (body data is base64url, https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.messages.attachments#MessagePartBody)
// - users.getProfile: https://developers.google.com/workspace/gmail/api/reference/rest/v1/users/getProfile
//
// The watch polls; it does not use users.watch, so no Pub/Sub topic is needed.
//
// Mail is data to inspect. Its subject, sender, body, and links go to the rules and the judge queue
// only; never to the logs, and never cut out into a notice (the card's one line is made in judge.ts).
// An instruction inside a mail ("家族に知らせないで") changes nothing here.

import { requireMember } from "./auth";
import type { ExternalBudget } from "./budget";
import { errorResponse, json } from "./http";
import { firstLink, worthAsking } from "./inbound";
import { enqueueJudge, JUDGE_TEXT_MAX_CHARS, normalizeDomain, type JudgePayload } from "./judge";
import { sendPush } from "./push";
import { judgeByRules } from "./rules";
import { openText, sealText } from "./secretbox";

const AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth";
const TOKEN_URL = "https://oauth2.googleapis.com/token";
// POST the token as a form parameter. 200 means revoked, 400 comes with an error code.
const REVOKE_URL = "https://oauth2.googleapis.com/revoke";
const GMAIL_API = "https://gmail.googleapis.com/gmail/v1/users/me";

/** Reading only. The watch never changes her mailbox. */
export const GMAIL_SCOPE = "https://www.googleapis.com/auth/gmail.readonly";
/** How long a consent URL from GET /gmail/connect can be used. */
export const STATE_LIFETIME_MS = 15 * 60_000;
/** Google ends a Testing app's grant after 7 days; the family is told a day before. */
export const RENEW_NOTICE_AFTER_MS = 6 * 24 * 3600_000;
/** Mails read per family per tick; the rest wait for the next tick. */
export const MESSAGES_PER_FAMILY = 10;
const FAMILIES_PER_TICK = 5;
/** Refresh and one page of history, at least, before a family is started. */
const CALLS_TO_START = 2;
const SENDER_MAX_CHARS = 500;
const LINKS_KEPT = 5;

/** Where Google's redirect sends the browser back. ASWebAuthenticationSession on the iPhone catches it. */
const APP_RETURN = "mimamori://gmail";

const EXPIRED_BODY = "Gmail の許可の取り直しが要ります";
const RENEW_SOON_BODY = "Gmail の許可がもうすぐ切れます";

/**
 * The Google OAuth client, or null while the author has not set it up. GOOGLE_CLIENT_ID and
 * GOOGLE_CLIENT_SECRET are left out of secrets.required in wrangler.jsonc on purpose: `wrangler deploy`
 * fails while a required secret is missing (developers.cloudflare.com/workers/wrangler/configuration/
 * #secrets-configuration-property), and the rest of the server must keep deploying until the author
 * has made the client. So they are not in the generated Env, and are read here by name.
 */
function googleClient(env: Env): { id: string; secret: string } | null {
  const vars = env as unknown as Record<string, unknown>;
  const id = vars.GOOGLE_CLIENT_ID;
  const secret = vars.GOOGLE_CLIENT_SECRET;
  return typeof id === "string" && id !== "" && typeof secret === "string" && secret !== "" ? { id, secret } : null;
}

interface GrantState {
  /** Family id. */
  f: string;
  /** When the state was made (ms). */
  t: number;
}

function redirectUri(request: Request): string {
  return `${new URL(request.url).origin}/gmail/callback`;
}

function back(result: "connected" | "denied" | "failed"): Response {
  return new Response(null, { status: 302, headers: { Location: `${APP_RETURN}?result=${result}` } });
}

// ---------------------------------------------------------------------------------------------
// The grant

/**
 * GET /gmail/connect: `{ url, grantedAt }`. The URL is Google's consent screen for reading mail; the
 * app opens it in ASWebAuthenticationSession. Only the protected member connects: it is her inbox.
 * `grantedAt` is when the current grant was given, or null when there is none.
 */
export async function connectRoute(request: Request, env: Env): Promise<Response> {
  const me = await requireMember(request, env);
  if (me.role !== "protected") return errorResponse(403, "protected_only");
  const client = googleClient(env);
  if (!client) return errorResponse(503, "gmail_not_configured");

  // Sealed (AES-GCM), so it can be neither read nor made outside the server.
  const state: GrantState = { f: me.familyId, t: Date.now() };
  const url = new URL(AUTH_URL);
  url.search = new URLSearchParams({
    client_id: client.id,
    redirect_uri: redirectUri(request),
    response_type: "code",
    scope: GMAIL_SCOPE,
    access_type: "offline",
    prompt: "consent",
    state: await sealText(env.TOKEN_ENC_KEY, JSON.stringify(state)),
  }).toString();

  const row = await env.DB.prepare("SELECT granted_at FROM gmail_auth WHERE family_id = ?")
    .bind(me.familyId)
    .first<{ granted_at: number }>();
  return json({ url: url.toString(), grantedAt: row ? new Date(row.granted_at).toISOString() : null });
}

async function readState(env: Env, value: string | null): Promise<GrantState | null> {
  if (!value) return null;
  try {
    const state = JSON.parse(await openText(env.TOKEN_ENC_KEY, value)) as Partial<GrantState>;
    if (typeof state.f !== "string" || typeof state.t !== "number") return null;
    const age = Date.now() - state.t;
    if (age < 0 || age > STATE_LIFETIME_MS) return null;
    return { f: state.f, t: state.t };
  } catch {
    return null;
  }
}

/**
 * GET /gmail/callback: Google sends her browser here with a code. The refresh token is sealed with
 * TOKEN_ENC_KEY and kept with the mailbox's current history id, so mail from before the grant is never
 * read. A new grant replaces the old row and clears the notice flag. Answers with a redirect to the app.
 */
export async function callbackRoute(request: Request, env: Env): Promise<Response> {
  const params = new URL(request.url).searchParams;
  const state = await readState(env, params.get("state"));
  if (!state) return back("failed");
  if (params.get("error")) return back("denied");
  const code = params.get("code");
  if (!code) return back("failed");

  const client = googleClient(env);
  if (!client) return back("failed");
  const family = await env.DB.prepare("SELECT id FROM families WHERE id = ?").bind(state.f).first<{ id: string }>();
  if (!family) return back("failed");

  const res = await googleFetch(TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      code,
      client_id: client.id,
      client_secret: client.secret,
      redirect_uri: redirectUri(request),
      grant_type: "authorization_code",
    }).toString(),
  });
  if (!res?.ok) {
    console.warn("gmail code exchange failed", res?.status ?? "network");
    return back("failed");
  }
  const tokens = (await res.json().catch(() => ({}))) as {
    access_token?: string;
    refresh_token?: string;
    scope?: string;
  };
  // She can leave reading mail unticked on Google's screen.
  if (!(tokens.scope ?? "").split(" ").includes(GMAIL_SCOPE)) return back("denied");
  if (!tokens.access_token || !tokens.refresh_token) return back("failed");

  const historyId = await currentHistoryId(tokens.access_token);
  if (historyId === null) return back("failed");

  const now = Date.now();
  await env.DB.prepare(
    `INSERT INTO gmail_auth (family_id, refresh_token_enc, granted_at, last_history_id, expired_notified_at)
     VALUES (?, ?, ?, ?, NULL)
     ON CONFLICT (family_id) DO UPDATE SET refresh_token_enc = excluded.refresh_token_enc,
       granted_at = excluded.granted_at, last_history_id = excluded.last_history_id, expired_notified_at = NULL,
       partial_record_id = NULL, partial_message_ids = NULL`,
  )
    .bind(state.f, await sealText(env.TOKEN_ENC_KEY, tokens.refresh_token), now, historyId)
    .run();
  return back("connected");
}

/**
 * Revokes one family's Gmail grant from its sealed refresh token.
 * Returns true when Google no longer holds the grant, including when it was already revoked or expired.
 */
export async function revokeGmailGrant(env: Env, refreshTokenEnc: string): Promise<boolean> {
  const token = await openText(env.TOKEN_ENC_KEY, refreshTokenEnc);
  let res: Response;
  try {
    res = await fetch(REVOKE_URL, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ token }).toString(),
    });
  } catch {
    return false;
  }
  if (res.ok) return true;
  if (res.status === 400) {
    const body = (await res.json().catch(() => ({}))) as { error?: string };
    return body.error === "invalid_token";
  }
  return false;
}

// ---------------------------------------------------------------------------------------------
// The watch

interface GrantRow {
  family_id: string;
  refresh_token_enc: string;
  granted_at: number;
  last_history_id: string | null;
  expired_notified_at: number | null;
  /** #174: the history record the last tick stopped inside, and the mails it handled there (JSON). */
  partial_record_id: string | null;
  partial_message_ids: string | null;
}

/** A fetch to Google, or null when the network failed. */
async function googleFetch(url: string, init: RequestInit): Promise<Response | null> {
  try {
    return await fetch(url, init);
  } catch {
    return null;
  }
}

async function currentHistoryId(accessToken: string): Promise<string | null> {
  const res = await googleFetch(`${GMAIL_API}/profile`, { headers: { Authorization: `Bearer ${accessToken}` } });
  if (!res?.ok) return null;
  const body = (await res.json().catch(() => ({}))) as { historyId?: unknown };
  return typeof body.historyId === "string" && /^\d+$/.test(body.historyId) ? body.historyId : null;
}

type Refreshed = { kind: "ok"; accessToken: string } | { kind: "dead" } | { kind: "error" };

async function refresh(env: Env, client: { id: string; secret: string }, sealed: string): Promise<Refreshed> {
  let refreshToken: string;
  try {
    refreshToken = await openText(env.TOKEN_ENC_KEY, sealed);
  } catch {
    // Sealed with another key: nothing can bring it back, so it is as good as revoked.
    return { kind: "dead" };
  }
  const res = await googleFetch(TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: client.id,
      client_secret: client.secret,
      grant_type: "refresh_token",
      refresh_token: refreshToken,
    }).toString(),
  });
  if (!res) return { kind: "error" };
  const body = (await res.json().catch(() => ({}))) as { access_token?: string; error?: string };
  if (res.ok && body.access_token) return { kind: "ok", accessToken: body.access_token };
  if (body.error === "invalid_grant") return { kind: "dead" };
  console.warn("gmail refresh failed", res.status, typeof body.error === "string" ? body.error.slice(0, 40) : "");
  return { kind: "error" };
}

async function familyMembers(env: Env, familyId: string): Promise<string[]> {
  const rows = await env.DB.prepare("SELECT id FROM members WHERE family_id = ? AND role = 'family'")
    .bind(familyId)
    .all<{ id: string }>();
  return rows.results.map((r) => r.id);
}

/**
 * Sends one notice to the family's members. False, so a later tick sends it again, when the budget could
 * not cover them, or when some member has a device and it reached none of them (APNs failed), as
 * openCase does (src/cases.ts). A family with no device at all counts as told: nothing could reach it.
 */
async function tellFamily(env: Env, familyId: string, body: string, budget: ExternalBudget): Promise<boolean> {
  const results = await sendPush(env, await familyMembers(env, familyId), { body, threadId: "gmail" }, budget);
  if (results.some((r) => r.status === "skipped" && r.reason === "no_budget")) return false;
  const reachable = results.filter((r) => r.status !== "skipped");
  return reachable.length === 0 || reachable.some((r) => r.status === "sent");
}

/**
 * Six days after the grant, once: the family is told to take it again before Google ends it. The flag
 * (expired_notified_at) is claimed before sending, and given back when it reached nobody.
 */
async function warnBeforeExpiry(env: Env, grant: GrantRow, now: number, budget: ExternalBudget): Promise<void> {
  if (grant.expired_notified_at !== null || now - grant.granted_at < RENEW_NOTICE_AFTER_MS) return;
  const claim = await env.DB.prepare(
    "UPDATE gmail_auth SET expired_notified_at = ? WHERE family_id = ? AND granted_at = ? AND expired_notified_at IS NULL",
  )
    .bind(now, grant.family_id, grant.granted_at)
    .run();
  if (claim.meta.changes !== 1) return;
  if (!(await tellFamily(env, grant.family_id, RENEW_SOON_BODY, budget))) {
    await env.DB.prepare("UPDATE gmail_auth SET expired_notified_at = NULL WHERE family_id = ? AND expired_notified_at = ?")
      .bind(grant.family_id, now)
      .run();
  }
}

/**
 * Google refused the refresh token (invalid_grant): the grant ran out or she took it back. The family
 * is told once and the row goes, which stops the watch until she grants again. When the budget could
 * not cover the notice, or APNs failed for every device, the row stays and the next tick tries again.
 */
async function endGrant(env: Env, grant: GrantRow, budget: ExternalBudget): Promise<void> {
  console.warn("gmail grant ended");
  if (!(await tellFamily(env, grant.family_id, EXPIRED_BODY, budget))) return;
  // Only this grant: one she gave again meanwhile has another granted_at.
  await env.DB.prepare("DELETE FROM gmail_auth WHERE family_id = ? AND granted_at = ?")
    .bind(grant.family_id, grant.granted_at)
    .run();
}

interface HistoryPage {
  history?: Array<{ id?: string; messagesAdded?: Array<{ message?: { id?: string; labelIds?: string[] } }> }>;
  nextPageToken?: string;
  historyId?: string;
}

interface MessagePart {
  mimeType?: string;
  filename?: string;
  headers?: Array<{ name?: string; value?: string }>;
  body?: { data?: string; attachmentId?: string };
  parts?: MessagePart[];
}

/** Where a tick stopped: the last whole history record read, and the mails handled in the next one. */
interface Progress {
  historyId: string;
  partialRecordId: string | null;
  partialIds: string[];
}

/** The partial record saved by the last tick, or null (none, or a value this code did not write). */
function savedPartial(grant: GrantRow): { recordId: string; ids: string[] } | null {
  if (grant.partial_record_id === null || grant.partial_message_ids === null) return null;
  let ids: unknown;
  try {
    ids = JSON.parse(grant.partial_message_ids);
  } catch {
    return null;
  }
  if (!Array.isArray(ids) || !ids.every((id) => typeof id === "string")) return null;
  return { recordId: grant.partial_record_id, ids };
}

/**
 * Reads the inbox after last_history_id and queues what the rules are unsure of.
 *
 * last_history_id only moves past whole history records. A record can carry several mails, so when a
 * tick stops inside one (a failed queue send, the per-tick cap, the budget), the mails it already
 * handled there are saved with it (partial_record_id, partial_message_ids) and the next tick skips them
 * instead of queueing them a second time (#174).
 */
async function readNewMail(
  env: Env,
  grant: GrantRow & { last_history_id: string },
  accessToken: string,
  budget: ExternalBudget,
): Promise<void> {
  const auth = { Authorization: `Bearer ${accessToken}` };
  const saved = savedPartial(grant);
  const seen = new Set<string>();
  let done = grant.last_history_id;
  let read = 0;
  let pageToken: string | undefined;

  const stop = (recordId: string, handled: string[]) =>
    saveProgress(env, grant, {
      historyId: done,
      partialRecordId: handled.length > 0 ? recordId : null,
      partialIds: handled,
    });

  for (;;) {
    if (!budget.take()) break;
    const url = new URL(`${GMAIL_API}/history`);
    url.searchParams.set("startHistoryId", grant.last_history_id);
    url.searchParams.set("historyTypes", "messageAdded");
    url.searchParams.set("labelId", "INBOX");
    if (pageToken) url.searchParams.set("pageToken", pageToken);
    const res = await googleFetch(url.toString(), { headers: auth });
    if (res?.status === 404) {
      // Google no longer has history that far back. Start again from now; the gap is not read.
      console.warn("gmail history reset");
      const now = budget.take() ? await currentHistoryId(accessToken) : null;
      if (now !== null) await saveProgress(env, grant, { historyId: now, partialRecordId: null, partialIds: [] });
      return;
    }
    if (!res?.ok) {
      console.warn("gmail history failed", res?.status ?? "network");
      break;
    }
    const page = (await res.json().catch(() => ({}))) as HistoryPage;

    for (const record of page.history ?? []) {
      const recordId = record.id;
      if (typeof recordId !== "string" || !/^\d+$/.test(recordId)) continue;
      const handled = saved?.recordId === recordId ? [...saved.ids] : [];
      for (const id of handled) seen.add(id);
      for (const added of record.messagesAdded ?? []) {
        const id = added.message?.id;
        const labels = added.message?.labelIds ?? [];
        if (!id || seen.has(id) || labels.includes("SENT") || labels.includes("DRAFT")) continue;
        if (read >= MESSAGES_PER_FAMILY || !budget.take()) return stop(recordId, handled);
        read += 1;
        if (!(await judgeMessage(env, grant.family_id, id, auth))) return stop(recordId, handled);
        seen.add(id);
        handled.push(id);
      }
      done = recordId;
    }
    if (!page.nextPageToken) {
      if (typeof page.historyId === "string" && /^\d+$/.test(page.historyId)) done = page.historyId;
      break;
    }
    pageToken = page.nextPageToken;
  }
  // No whole record was read (the history call failed or the budget ran out before it): keep what the
  // last tick saved, partial record included.
  if (done === grant.last_history_id) return;
  await saveProgress(env, grant, { historyId: done, partialRecordId: null, partialIds: [] });
}

/**
 * Saves where this tick stopped, only from the values this tick started with (another tick that moved
 * the row meanwhile wins). Also when last_history_id stays: the partial record may have grown.
 */
async function saveProgress(
  env: Env,
  grant: GrantRow & { last_history_id: string },
  progress: Progress,
): Promise<void> {
  const ids = progress.partialRecordId === null ? null : JSON.stringify(progress.partialIds);
  if (
    progress.historyId === grant.last_history_id &&
    progress.partialRecordId === grant.partial_record_id &&
    ids === grant.partial_message_ids
  ) {
    return;
  }
  await env.DB.prepare(
    `UPDATE gmail_auth SET last_history_id = ?, partial_record_id = ?, partial_message_ids = ?
      WHERE family_id = ? AND granted_at = ? AND last_history_id = ?
        AND partial_record_id IS ? AND partial_message_ids IS ?`,
  )
    .bind(
      progress.historyId,
      progress.partialRecordId,
      ids,
      grant.family_id,
      grant.granted_at,
      grant.last_history_id,
      grant.partial_record_id,
      grant.partial_message_ids,
    )
    .run();
}

/**
 * Fetches one mail and hands it to the rules and to the judge queue (worthAsking). True when
 * the mail is dealt with (including gone or unreadable), false when it should be tried again.
 */
async function judgeMessage(env: Env, familyId: string, id: string, auth: Record<string, string>): Promise<boolean> {
  const res = await googleFetch(`${GMAIL_API}/messages/${encodeURIComponent(id)}?format=full`, { headers: auth });
  if (res?.status === 404) return true;
  if (!res?.ok) {
    console.warn("gmail message failed", res?.status ?? "network");
    return false;
  }
  const message = (await res.json().catch(() => null)) as { labelIds?: string[]; payload?: MessagePart } | null;
  if (!message?.payload) return true;
  const labels = message.labelIds ?? [];
  if (labels.includes("SENT") || labels.includes("DRAFT")) return true;

  const payload = mailPayload(message.payload);
  const rule = judgeByRules({ source: "gmail", ...payload });
  if (!worthAsking(rule)) return true;
  try {
    await enqueueJudge(env, { familyId, source: "gmail", payload });
    return true;
  } catch (error) {
    console.warn("gmail enqueue failed", error instanceof Error ? error.name : typeof error);
    return false;
  }
}

/** The sender's address, the subject and the text, and the first link, for the rules and the queue. */
export function mailPayload(part: MessagePart): JudgePayload {
  const header = (name: string) =>
    part.headers?.find((h) => h.name?.toLowerCase() === name)?.value?.trim() ?? "";
  // Not decoded: an encoded word may only stand for a display name, never for the address.
  const from = header("from");
  const subject = decodeWords(header("subject"));
  const { plain, html } = bodies(part);
  const hrefs = html.flatMap((h) => [...h.matchAll(/href\s*=\s*["']?(https?:\/\/[^"'\s>]+)/gi)].map((m) => m[1] ?? ""));
  const body = plain.length > 0 ? plain.join("\n") : html.map(htmlToText).join("\n");
  const links = [...new Set(hrefs.filter((l) => l !== "" && !body.includes(l)))].slice(0, LINKS_KEPT);
  const text = cut([subject, body, ...links].filter((s) => s !== "").join("\n"), JUDGE_TEXT_MAX_CHARS);

  const out: JudgePayload = { text };
  // Left out rather than cut, since a cut address could end on an official domain.
  const address = senderAddress(from);
  if (address && [...address].length <= SENDER_MAX_CHARS) out.sender = address;
  const url = firstLink(links[0] ?? "") ?? firstLink(text);
  if (url) out.url = url;
  const domain = normalizeDomain({ familyId: "", source: "gmail", payload: out });
  if (domain) out.domain = domain;
  return out;
}

/**
 * The addr-spec of From: the last <...> when it ends the header, or the whole header when it is a
 * bare address. The display name is left out, since it can say anything, an official address in
 * angle brackets included (#170). A From of any other shape, a list of mailboxes included, gives no
 * sender, so nothing in it counts as official. The local part is printable ASCII (RFC 5322 atext and
 * dots) and the domain is ASCII labels, so the rules see the same domain Gmail does.
 */
function senderAddress(from: string): string {
  const value = from.trim();
  // A comma outside quotes means a list of mailboxes, which a mail from one sender does not have.
  if (value.replace(/"(?:[^"\\]|\\.)*"/g, "").includes(",")) return "";
  const bracketed = /<([^<>\s]*)>$/.exec(value);
  const address = bracketed ? (bracketed[1] ?? "") : value;
  // Checked on the raw characters, before the rules apply NFKC and read the domain as a URL host: a
  // "?", "/", "#" or a full-width "＠" in the domain would make a host there that is not the domain.
  const at = address.lastIndexOf("@");
  const local = address.slice(0, at);
  const domain = address.slice(at + 1);
  return at > 0 && /^[A-Za-z0-9!#$%&'*+\-/=?^_`{|}~.]+$/.test(local) && /^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+\.?$/.test(domain)
    ? address
    : "";
}

function cut(text: string, max: number): string {
  const c = [...text];
  return c.length > max ? c.slice(0, max).join("") : text;
}

/** text/plain and text/html parts, attachments left out. */
function bodies(part: MessagePart, out: { plain: string[]; html: string[] } = { plain: [], html: [] }) {
  const type = (part.mimeType ?? "").toLowerCase();
  if (!part.filename && !part.body?.attachmentId && part.body?.data) {
    const charset = /charset="?([^";\s]+)/i.exec(contentType(part))?.[1];
    if (type === "text/plain") out.plain.push(decodeData(part.body.data, charset));
    else if (type === "text/html") out.html.push(decodeData(part.body.data, charset));
  }
  for (const child of part.parts ?? []) bodies(child, out);
  return out;
}

function contentType(part: MessagePart): string {
  return part.headers?.find((h) => h.name?.toLowerCase() === "content-type")?.value ?? "";
}

function bytesOf(base64url: string): Uint8Array {
  const b64 = base64url.replace(/-/g, "+").replace(/_/g, "/");
  const padded = b64 + "=".repeat((4 - (b64.length % 4)) % 4);
  return Uint8Array.from(atob(padded), (c) => c.charCodeAt(0));
}

function decodeBytes(bytes: Uint8Array, charset?: string): string {
  try {
    return new TextDecoder(charset ?? "utf-8").decode(bytes);
  } catch {
    return new TextDecoder("utf-8").decode(bytes);
  }
}

function decodeData(data: string, charset?: string): string {
  try {
    return decodeBytes(bytesOf(data), charset);
  } catch {
    return "";
  }
}

/** RFC 2047 encoded words ("=?UTF-8?B?...?="), in case a header comes undecoded. */
function decodeWords(value: string): string {
  return value.replace(/=\?([^?]+)\?([bq])\?([^?]*)\?=/gi, (whole, charset: string, kind: string, data: string) => {
    try {
      if (kind.toLowerCase() === "b") return decodeBytes(Uint8Array.from(atob(data), (c) => c.charCodeAt(0)), charset);
      const bytes = data
        .replace(/_/g, " ")
        .replace(/=([0-9a-f]{2})/gi, (_, h: string) => String.fromCharCode(parseInt(h, 16)));
      return decodeBytes(Uint8Array.from(bytes, (c) => c.charCodeAt(0)), charset);
    } catch {
      return whole;
    }
  });
}

function htmlToText(html: string): string {
  return html
    .replace(/<(style|script|head)[\s\S]*?<\/\1>/gi, " ")
    .replace(/<br\s*\/?>|<\/(p|div|tr|li|h\d)>/gi, "\n")
    .replace(/<[^>]*>/g, " ")
    .replace(/&nbsp;/gi, " ")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&quot;/gi, '"')
    .replace(/&#39;|&apos;/gi, "'")
    .replace(/&#(\d+);/g, (_, n: string) => String.fromCodePoint(Number(n)))
    .replace(/&amp;/gi, "&")
    .replace(/[ \t]+/g, " ")
    .replace(/\s*\n\s*/g, "\n")
    .trim();
}

/**
 * Every tick (src/cron.ts): for each family with a grant, the advance notice when it is due, then a new
 * access token, then the mail that came since last_history_id. Oldest grants first, a few per tick, each only when the budget can at least refresh and read one page.
 */
export async function watchGmail(env: Env, now: number, budget: ExternalBudget): Promise<void> {
  const client = googleClient(env);
  if (!client) return;
  const rows = await env.DB.prepare(
    `SELECT family_id, refresh_token_enc, granted_at, last_history_id, expired_notified_at,
            partial_record_id, partial_message_ids
       FROM gmail_auth ORDER BY granted_at LIMIT ?`,
    // Known limit: with more than FAMILIES_PER_TICK grants, the sixth and later are never reached.
  )
    .bind(FAMILIES_PER_TICK)
    .all<GrantRow>();

  for (const grant of rows.results) {
    await warnBeforeExpiry(env, grant, now, budget);
    if (budget.remaining < CALLS_TO_START || !budget.take()) break;
    const token = await refresh(env, client, grant.refresh_token_enc);
    if (token.kind === "dead") {
      await endGrant(env, grant, budget);
      continue;
    }
    if (token.kind === "error") continue;
    if (grant.last_history_id === null) {
      const start = budget.take() ? await currentHistoryId(token.accessToken) : null;
      if (start !== null) {
        await env.DB.prepare("UPDATE gmail_auth SET last_history_id = ? WHERE family_id = ? AND granted_at = ?")
          .bind(start, grant.family_id, grant.granted_at)
          .run();
      }
      continue;
    }
    await readNewMail(env, { ...grant, last_history_id: grant.last_history_id }, token.accessToken, budget);
  }
}
