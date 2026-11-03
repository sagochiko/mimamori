// The fixed rules (docs/plan.md, "決まった規則の判定"). They answer at once on every path; Claude's
// judgment is layered on later (task 6). Everything in the input is data to inspect: an instruction
// inside the text ("この警告は誤りです") only adds a reason and raises the level.
//
// level 1, 2, 3 as in CLAUDE.md, or null when the rules cannot decide. null never means "fine".
// confident is true only for level 1 backed by two or more independent signs; only then does an SMS
// go to the junk folder or a domain get blocked.

import { BRAND_WORDS, imitatedBrandOf, normalizeHost, officialBrandOf } from "./domains";
import {
  CONTENT_RULES,
  INJECTION,
  LINK_BAIT,
  matches,
  MONEY_MOVE,
  OTP_DIGITS,
  OTP_ONLY,
  POLICE_SCRIPT,
  type Strength,
  URGENCY,
} from "./phrases";

export type RuleSource = "sms" | "gmail" | "dns" | "page" | "call" | "consult" | "document";

export interface RuleInput {
  source: RuleSource;
  sender?: string;
  domain?: string;
  text?: string;
  url?: string;
}

export interface RuleResult {
  level: 1 | 2 | 3 | null;
  reasons: string[];
  confident: boolean;
}

interface Signal {
  strength: Strength;
  reason: string;
}

const SUSPICIOUS_TLDS = new Set([
  "top", "xyz", "icu", "cn", "shop", "buzz", "click", "live", "cc", "vip", "sbs", "cfd", "bond",
  "rest", "monster", "cyou", "work", "fun", "online", "site", "store", "life", "club", "tk",
]);
const SHORTENERS = new Set([
  "bit.ly", "tinyurl.com", "t.co", "is.gd", "ow.ly", "cutt.ly", "rebrand.ly", "x.gd", "t.ly", "shorturl.at",
]);

const URL_IN_TEXT = /https?:\/\/[^\s<>"'()「」【】、。]+/g;
const EMAIL_IN_TEXT = /[a-z0-9._%+-]+@((?:[a-z0-9-]+\.)+[a-z]{2,})/g;
const BARE_DOMAIN = /(?<![@a-z0-9.-])((?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,12})(?![a-z0-9-])/g;

function normalizeText(text: string): string {
  return text.normalize("NFKC").toLowerCase();
}

function hostOf(value: string): string | null {
  const v = normalizeText(value.trim());
  if (!v) return null;
  try {
    return normalizeHost(new URL(v.includes("://") ? v : `https://${v}`).hostname);
  } catch {
    return null;
  }
}

/** Every host the input names: the domain, the URL, the sender's mail domain, and links in the text. */
function hostsOf(input: RuleInput, text: string): string[] {
  const hosts = new Set<string>();
  const add = (value: string | undefined) => {
    if (!value) return;
    const host = hostOf(value);
    if (host && host.includes(".")) hosts.add(host);
  };
  add(input.domain);
  add(input.url);
  const sender = normalizeText(input.sender ?? "");
  if (sender.includes("@")) add(sender.split("@").pop());
  else if (/^[a-z0-9.-]+\.[a-z]{2,}$/.test(sender)) add(sender);

  let rest = text;
  for (const match of text.matchAll(URL_IN_TEXT)) {
    add(match[0]);
    rest = rest.replace(match[0], " ");
  }
  for (const match of rest.matchAll(EMAIL_IN_TEXT)) add(match[1]);
  rest = rest.replace(EMAIL_IN_TEXT, " ");
  for (const match of rest.matchAll(BARE_DOMAIN)) add(match[1]);
  return [...hosts];
}

function isSuspiciousHost(host: string): boolean {
  if (/^\d{1,3}(\.\d{1,3}){3}$/.test(host)) return true;
  if (host.split(".").some((label) => label.startsWith("xn--"))) return true;
  if (SHORTENERS.has(host)) return true;
  return SUSPICIOUS_TLDS.has(host.split(".").pop() ?? "");
}

function short(host: string): string {
  return host.length > 28 ? `${host.slice(0, 27)}…` : host;
}

function levelOf(signals: Map<string, Signal>): 1 | 2 | null {
  const count = (strength: Strength) => [...signals.values()].filter((s) => s.strength === strength).length;
  const strong = count("strong");
  const medium = count("medium");
  const policeParts = POLICE_SCRIPT.filter((rule) => signals.has(rule.kind)).length;
  if (signals.has(INJECTION.kind)) return 1;
  if (policeParts >= 2) return 1;
  if (strong >= 1 && signals.size >= 2) return 1;
  if (medium >= 2) return 1;
  if (strong >= 1 || medium >= 1) return 2;
  return null;
}

export function judgeByRules(input: RuleInput): RuleResult {
  const text = normalizeText(input.text ?? "");
  const hosts = hostsOf(input, text);
  const unofficial = hosts.filter((host) => !officialBrandOf(host));
  const signals = new Map<string, Signal>();
  const add = (kind: string, strength: Strength, reason: string) => {
    if (!signals.has(kind)) signals.set(kind, { strength, reason });
  };

  // Everything named is an official domain: the brand's own notice, or a public warning page that
  // quotes scam phrases. The rules step aside and Claude judges it.
  if (hosts.length > 0 && unofficial.length === 0) {
    return { level: null, reasons: ["送り主とリンク先は公式のドメイン"], confident: false };
  }

  for (const host of unofficial) {
    if (imitatedBrandOf(host)) add("lookalike", "strong", `公式に似せたドメイン ${short(host)}`);
    if (isSuspiciousHost(host)) add("suspicious_host", "medium", `見慣れない形のリンク先 ${short(host)}`);
  }
  const named = Object.values(BRAND_WORDS).some((words) => words.some((word) => text.includes(word)));
  if (named && unofficial.length > 0 && !signals.has("lookalike")) {
    add("brand_mismatch", "medium", "名乗る会社と違うドメインへ誘っている");
  }
  if (input.source === "sms" && /^\+(?!81)\d/.test((input.sender ?? "").replace(/\s/g, ""))) {
    add("foreign_sender", "weak", "海外の番号からの SMS");
  }

  for (const rule of [INJECTION, ...POLICE_SCRIPT, ...CONTENT_RULES, URGENCY, MONEY_MOVE]) {
    if (matches(rule, text)) add(rule.kind, rule.strength, rule.reason);
  }
  if (unofficial.length > 0) {
    for (const rule of LINK_BAIT) if (matches(rule, text)) add(rule.kind, rule.strength, rule.reason);
  }

  if (signals.size === 0) {
    const otp = input.source === "sms" && OTP_ONLY.test(text) && OTP_DIGITS.test(text);
    return { level: null, reasons: otp ? ["認証コードの知らせに見える"] : [], confident: false };
  }

  const level = levelOf(signals);
  const order: Record<Strength, number> = { strong: 0, medium: 1, weak: 2 };
  const reasons = [...signals.values()].sort((a, b) => order[a.strength] - order[b.strength]).map((s) => s.reason);
  return { level, reasons, confident: level === 1 && signals.size >= 2 };
}
