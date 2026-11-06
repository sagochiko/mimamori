// The fixed rules (docs/plan.md, "決まった規則の判定"). They answer at once on every path; Claude's
// judgment is layered on later (task 6). Everything in the input is data to inspect: an instruction
// inside the text ("この警告は誤りです") only adds a reason and raises the level.
//
// level 1, 2, 3 as in CLAUDE.md, or null when the rules cannot decide. null never means "fine".
// An official domain only means no domain sign is added for it; the text is always checked, since a
// sender can be forged and anyone can write an official domain into a message.
// confident is true only for level 1 with a strong sign that genuine messages do not give, at least
// two independent signs that are not weak, and no official sender or link; only then does an SMS go
// to the junk folder or a domain get blocked. Two rules written for the same thing that match one
// phrase are one sign.

import { BRAND_WORDS, type HostTrust, imitatedBrandOf, normalizeHost, trustOf } from "./domains";
import {
  blankOut,
  CODE_GUARD,
  CONTENT_RULES,
  CREDENTIAL_GUARD,
  CREDENTIAL_FROM_CODE,
  INJECTION,
  LINK_BAIT,
  matchSpans,
  MONEY_MOVE,
  NOTICE_IGNORE,
  OTP_DIGITS,
  OTP_ONLY,
  PHONE_NUMBER,
  POLICE_SCRIPT,
  type PhraseRule,
  type Strength,
  tellingOf,
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
  kind: string;
  strength: Strength;
  reason: string;
  /** Where a phrase rule matched in the text. Empty for signs that do not come from a phrase. */
  spans: Array<[number, number]>;
}

interface NamedHost extends HostTrust {
  host: string;
  /** Named as a mail address (the sender, or an address in the text), not as a link or a domain. */
  address: boolean;
  /** Only written in the text without https://, as in "【Amazon.co.jp】". A name more than a link. */
  bare: boolean;
  /**
   * The page's own address (its URL or domain, not a link nested in its query): where she already
   * is, not a link she is led to. Only for pages.
   */
  own: boolean;
  /** The mail sender's own domain, not an address written in the text. */
  fromSender: boolean;
}

const SUSPICIOUS_TLDS = new Set([
  "top",
  "xyz",
  "icu",
  "cn",
  "shop",
  "buzz",
  "click",
  "live",
  "cc",
  "vip",
  "sbs",
  "cfd",
  "bond",
  "rest",
  "monster",
  "cyou",
  "work",
  "fun",
  "online",
  "site",
  "store",
  "life",
  "club",
  "tk",
]);
const SHORTENERS = new Set([
  "bit.ly",
  "tinyurl.com",
  "t.co",
  "is.gd",
  "ow.ly",
  "cutt.ly",
  "rebrand.ly",
  "x.gd",
  "t.ly",
  "shorturl.at",
]);

const URL_IN_TEXT = /https?:\/\/[^\s<>"'()「」【】、。]+/g;
const EMAIL_IN_TEXT = /[a-z0-9._%+-]+@((?:[a-z0-9-]+\.)+[a-z]{2,})/g;
const BARE_DOMAIN = /(?<![@a-z0-9.-])((?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,12})(?![a-z0-9-])/g;

function normalizeText(text: string): string {
  return text.normalize("NFKC").toLowerCase();
}

function parseUrl(value: string): URL | null {
  const v = normalizeText(value.trim());
  if (!v) return null;
  try {
    return new URL(v.includes("://") ? v : `https://${v}`);
  } catch {
    return null;
  }
}

/** URLs carried inside a link's query, as in https://www.google.com/url?q=https://... */
function nestedUrls(url: URL): string[] {
  return [...url.searchParams.values()].filter((value) => /^https?:\/\//i.test(value.trim()));
}

/** Every host the input names: the domain, the URL, the sender's mail domain, and links in the text. */
function hostsOf(input: RuleInput, text: string): NamedHost[] {
  const hosts = new Map<string, NamedHost>();
  const put = (host: string, address: boolean, trust: HostTrust, bare = false, own = false, fromSender = false) => {
    const key = `${address}:${host}:${trust.trust}`;
    // The same host named both bare and as a link counts as a link. A page's own host stays its own
    // when the page links to itself.
    const before = hosts.get(key);
    if (host.includes(".") && !(bare && before)) {
      hosts.set(key, {
        host,
        address,
        bare,
        own: own || (before?.own ?? false),
        fromSender: fromSender || (before?.fromSender ?? false),
        ...trust,
      });
    }
  };
  const addAddress = (domain: string | undefined, fromSender = false) => {
    const url = domain ? parseUrl(domain) : null;
    if (url) put(normalizeHost(url.hostname), true, trustOf(url.hostname, true), false, false, fromSender);
  };
  const addLink = (value: string | undefined, depth = 0, bare = false, own = false) => {
    const url = value ? parseUrl(value) : null;
    if (!url) return;
    const inner = depth < 2 ? nestedUrls(url) : [];
    // A link that only passes the reader on is not the brand speaking, whoever runs the redirect.
    put(normalizeHost(url.hostname), false, trustOf(url.hostname, false, url.pathname, inner.length > 0), bare, own);
    for (const next of inner) addLink(next, depth + 1);
  };
  const page = input.source === "page";
  addLink(input.domain, 0, false, page);
  addLink(input.url, 0, false, page);
  const sender = normalizeText(input.sender ?? "");
  if (sender.includes("@")) addAddress(sender.split("@").pop(), true);
  else if (/^[a-z0-9.-]+\.[a-z]{2,}$/.test(sender)) addLink(sender);

  let rest = text;
  for (const match of text.matchAll(URL_IN_TEXT)) {
    addLink(match[0]);
    rest = rest.replace(match[0], " ");
  }
  for (const match of rest.matchAll(EMAIL_IN_TEXT)) addAddress(match[1]);
  rest = rest.replace(EMAIL_IN_TEXT, " ");
  for (const match of rest.matchAll(BARE_DOMAIN)) addLink(match[1], 0, true);
  return [...hosts.values()];
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

interface Sign {
  strength: Strength;
  kinds: Set<string>;
}

// The secrecy rules a genuine code notice can match (#51).
const POLICE_SECRECY = POLICE_SCRIPT.find((rule) => rule.kind === "police_secrecy")!;
const HUSH_KINDS = new Set([INJECTION.kind, POLICE_SECRECY.kind]);

const RANK: Record<Strength, number> = { strong: 0, medium: 1, weak: 2 };

// Rules written for the same thing, so one phrase can match both: "家族に言わないで" is both the
// injection rule's "keep the family out" and the fake-police secrecy. Only these pairs are merged;
// other rules that happen to overlap ("口座番号を入力" inside "口座 ... 悪用") stay separate signs, and
// a weak sign never joins two others into one.
const SAME_THING: ReadonlyArray<readonly [string, string]> = [[INJECTION.kind, "police_secrecy"]];

/** Two rules matched one phrase: a pair in SAME_THING whose matches cover mostly the same text. */
function samePhrase(a: Signal, b: Signal): boolean {
  if (!SAME_THING.some(([x, y]) => (a.kind === x && b.kind === y) || (a.kind === y && b.kind === x))) return false;
  return a.spans.some(([s1, e1]) =>
    b.spans.some(([s2, e2]) => 2 * (Math.min(e1, e2) - Math.max(s1, s2)) >= Math.max(e1 - s1, e2 - s2)),
  );
}

/** Signals merged into independent signs: rules that matched the same phrase are one sign. */
function signsOf(signals: Signal[]): Sign[] {
  const parent = signals.map((_, i) => i);
  const root = (i: number): number => (parent[i] === i ? i : (parent[i] = root(parent[i]!)));
  for (let i = 0; i < signals.length; i++) {
    for (let j = i + 1; j < signals.length; j++) {
      if (samePhrase(signals[i]!, signals[j]!)) parent[root(i)] = root(j);
    }
  }
  const signs = new Map<number, Sign>();
  signals.forEach((signal, i) => {
    const sign = signs.get(root(i)) ?? { strength: signal.strength, kinds: new Set<string>() };
    if (RANK[signal.strength] < RANK[sign.strength]) sign.strength = signal.strength;
    sign.kinds.add(signal.kind);
    signs.set(root(i), sign);
  });
  return [...signs.values()];
}

function levelOf(signs: Sign[]): 1 | 2 | null {
  const count = (strength: Strength) => signs.filter((s) => s.strength === strength).length;
  const strong = count("strong");
  const medium = count("medium");
  const policeParts = signs.filter((s) => POLICE_SCRIPT.some((rule) => s.kinds.has(rule.kind))).length;
  if (signs.some((s) => s.kinds.has(INJECTION.kind))) return 1;
  if (policeParts >= 2) return 1;
  if (strong >= 1 && signs.length >= 2) return 1;
  if (medium >= 2) return 1;
  if (strong >= 1 || medium >= 1) return 2;
  return null;
}

/** The weak sign for an SMS from a number outside Japan. Genuine overseas services send those too. */
export const FOREIGN_SENDER_REASON = "海外の番号からの SMS";

/** The one reason a message that is only a verification code gets. Its level stays null. */
export const CODE_ONLY_REASON = "認証コードの知らせに見える";

export function judgeByRules(input: RuleInput): RuleResult {
  const text = normalizeText(input.text ?? "");
  const hosts = hostsOf(input, text);
  // Hosts that are not the brand speaking. Official ones add no domain sign; the text is still read.
  const unofficial = hosts.filter((h) => h.trust !== "official");
  const unofficialLinks = unofficial.filter((h) => !h.address);
  const signals = new Map<string, Signal>();
  const add = (kind: string, strength: Strength, reason: string, spans: Array<[number, number]> = []) => {
    if (!signals.has(kind)) signals.set(kind, { kind, strength, reason, spans });
  };
  const check = (rule: PhraseRule) => {
    const spans = matchSpans(rule, text);
    if (spans.length > 0) add(rule.kind, rule.strength, rule.reason, spans);
  };

  for (const { host, trust, own } of unofficial) {
    // A free mail address or a user page belongs to the brand that runs the domain, so it is no
    // look-alike; it only stops counting as the brand speaking.
    if (trust !== "other") continue;
    if (imitatedBrandOf(host)) add("lookalike", "strong", `公式に似せたドメイン ${short(host)}`);
    // A page's own unusual host is the site she opened, not a link to an unusual place (#16): shops
    // on .shop, sites on new TLDs, and Japanese domain names are ordinary pages. Unless it also
    // imitates a brand, as amazon-co-jp.top does: then the odd shape is part of the fake.
    const lookalike = imitatedBrandOf(host) !== null;
    if ((!own || lookalike) && isSuspiciousHost(host)) add("suspicious_host", "medium", `見慣れない形のリンク先 ${short(host)}`);
  }
  const named = new Set(
    Object.entries(BRAND_WORDS)
      .filter(([, words]) => words.some((word) => text.includes(word)))
      .map(([brand]) => brand),
  );
  // A page that names a brand is not leading anywhere by its own address: a news article on a company,
  // a blog about a bank. Only links in its text count (#16).
  const elsewhere = unofficial.some((h) => !h.own && (!h.brand || !named.has(h.brand)));
  if (named.size > 0 && elsewhere && !signals.has("lookalike")) {
    add("brand_mismatch", "medium", "名乗る会社と違うドメインへ誘っている");
  }
  if (input.source === "sms" && /^\+(?!81)\d/.test((input.sender ?? "").replace(/\s/g, ""))) {
    add("foreign_sender", "weak", FOREIGN_SENDER_REASON);
  }

  // A message that is only a verification code: typing the code in is what it is for, and "don't
  // tell anyone" protects the code. Anything a scam would add makes it more than a code: a link that
  // is not official, a phone number, another part of the fake-police script, or moving money. The
  // digits are looked for after phone numbers are taken out, so "03-1234-5678" is no code.
  const hasPhone = PHONE_NUMBER.test(text);
  const plain =
    (input.source === "sms" || input.source === "gmail") &&
    unofficialLinks.length === 0 &&
    !hasPhone &&
    !POLICE_SCRIPT.some((rule) => rule.kind !== "police_secrecy" && matchSpans(rule, text).length > 0) &&
    matchSpans(MONEY_MOVE, text).length === 0;
  const codeOnly =
    plain && OTP_ONLY.test(text) && OTP_DIGITS.test(text.replace(new RegExp(PHONE_NUMBER.source, "g"), " "));

  check(INJECTION);
  // "このメッセージは無視して" counts only with a link that is not official. Genuine code messages
  // say it with a number to call, so a phone number alone does not make it count.
  if (unofficialLinks.length > 0) check(NOTICE_IGNORE);
  // A consultation that passes on a warning she heard or read (#81): the script's parts in it are what
  // the warning describes, so they are not signs, and Claude answers it. Text aimed at the app still is.
  const passedOn = input.source === "consult" && tellingOf(text) === "passed_on";
  if (!passedOn) for (const rule of POLICE_SCRIPT) if (!(codeOnly && rule.kind === "police_secrecy")) check(rule);
  for (const rule of CONTENT_RULES)
    check(codeOnly && rule.kind === CREDENTIAL_FROM_CODE.kind ? CREDENTIAL_FROM_CODE : rule);
  check(URGENCY);
  check(MONEY_MOVE);
  if (unofficial.length > 0) for (const rule of LINK_BAIT) check(rule);

  // A genuine notice says not to tell the family the code or the PIN (#51). Only where the message
  // can be taken as genuine on its own: an SMS that is only a code, or mail from an official sender
  // with nothing a scam adds. And only when the secrecy is all there is: the sentences that protect
  // the code (CREDENTIAL_GUARD, and in a code CODE_GUARD) are blanked out, and if the secrecy rules
  // then find nothing and no other sign was found, weak ones included, it is read as the notice. Any
  // other sign keeps the whole message as it was read, since a scam can add the genuine sentence.
  const officialSender =
    input.source === "gmail" && hosts.some((h) => h.address && h.trust === "official" && h.fromSender);
  const genuineShape = (codeOnly && input.source === "sms") || (officialSender && plain);
  if (genuineShape && [...signals.keys()].every((kind) => HUSH_KINDS.has(kind))) {
    const blanked = blankOut(codeOnly ? blankOut(text, CODE_GUARD) : text, CREDENTIAL_GUARD);
    const hushLeft =
      matchSpans(INJECTION, blanked).length > 0 || (!codeOnly && matchSpans(POLICE_SECRECY, blanked).length > 0);
    if (!hushLeft) signals.clear();
  }

  if (signals.size === 0) {
    return {
      level: null,
      reasons: codeOnly && input.source === "sms" ? [CODE_ONLY_REASON] : [],
      confident: false,
    };
  }

  const signs = signsOf([...signals.values()]);
  const level = levelOf(signs);
  const independent = signs.filter((s) => s.strength !== "weak").length;
  // An official sender or link (not a free mail address or a user page) means it may be the brand or
  // a public body warning about the scam it quotes. Never confident then, so a genuine warning does
  // not go to the junk folder; the level stays and Claude may lower it. Accepted trade-off: a scam
  // that adds an official link also stays out of the junk folder (eval/README.md). A domain written
  // without https://, as in "【Amazon.co.jp】", is a name that scams copy, so it does not count.
  const official = hosts.some((h) => h.trust === "official" && !h.bare);
  const confident = level === 1 && !official && signs.some((s) => s.strength === "strong") && independent >= 2;
  const reasons = [...signals.values()].sort((a, b) => RANK[a.strength] - RANK[b.strength]).map((s) => s.reason);
  // A code with only weak signs (an overseas number) is still a code; the SMS route reads this reason
  // to leave it off the judge queue (src/sms.ts).
  if (level === null && codeOnly && input.source === "sms") reasons.push(CODE_ONLY_REASON);
  return { level, reasons, confident };
}
