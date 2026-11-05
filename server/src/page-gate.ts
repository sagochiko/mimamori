// Which of the mother's pages go to Claude (#137). The rules answer every page at once and only their
// level draws the warning; this only picks the pages that also get Claude's look through the judge
// queue. It gives no level and adds no reason, so nothing here can cover a page or reach the family by
// itself: the family hears only of a level from the rules or from Claude.
//
// Not every page goes: she opens many, and most are articles, shops, and recipes. The ones picked are
// where a fake page asks for something: a page that speaks as a company from a host that is not the
// company's, a page with a field for a password or a card number, and a page that puts a phone number
// next to a warning. The page's text and URL are data; nothing in them is followed.
//
// No binding and no Node API, so eval/lib/score.ts can use it as well.

import { BRAND_WORDS, officialBrandOf } from "./rules/domains";
import { PHONE_NUMBER, URGENCY } from "./rules/phrases";
import type { RuleResult } from "./rules";

export interface PageSeen {
  url: string;
  text?: string;
  /** The content script saw a password or card number field on the page. Only true or false is sent. */
  hasSecretField?: boolean;
}

// Words of a page that speaks to her as the company's customer: an article that names the company
// ("楽天グループの決算", "Amazon.com はアメリカの会社") has none of them.
const SPEAKS_AS_BRAND =
  /サインイン|ログイン|アカウント|パスワード|会員情報|お客様情報|お客さま情報|本人確認|カード情報|お支払い(方法|情報)|支払い方法|ご利用(確認|状況)|sign[\s-]?in|log[\s-]?in|account/i;

// What fake security warnings and support pages say around the number they want her to call.
const SUPPORT_WORDS = /サポート|警告|ウイルス|ウィルス|感染|セキュリティ|ハッキング|乗っ取|不正|修復|故障/;

function textOf(page: PageSeen): string {
  return (page.text ?? "").normalize("NFKC").toLowerCase();
}

function host(page: PageSeen): string {
  try {
    return new URL(page.url).hostname;
  } catch {
    return "";
  }
}

/** The page names a company in BRAND_WORDS and talks to its customers, but its host is not the company's. */
export function speaksAsOtherBrand(page: PageSeen): boolean {
  const text = textOf(page);
  if (!SPEAKS_AS_BRAND.test(text)) return false;
  const own = officialBrandOf(host(page));
  return Object.entries(BRAND_WORDS).some(
    ([brand, words]) => brand !== own && words.some((w) => text.includes(w.normalize("NFKC").toLowerCase())),
  );
}

/** A phone number with a warning or urgency around it, as fake support pages show. */
export function callsForSupport(page: PageSeen): boolean {
  const text = textOf(page);
  if (!PHONE_NUMBER.test(text)) return false;
  return SUPPORT_WORDS.test(text) || URGENCY.patterns.some((p) => p.test(text));
}

/**
 * Whether a page from the mother's phone goes to Claude: a level or a sign from the rules, as before
 * #137, or one of the shapes above. Pages on her own network and from the family's phones are left out
 * by the route (src/page.ts) before this.
 */
export function pageWorthAsking(rule: RuleResult, page: PageSeen): boolean {
  if (rule.level !== null || rule.reasons.length > 0) return true;
  return page.hasSecretField === true || speaksAsOtherBrand(page) || callsForSupport(page);
}
