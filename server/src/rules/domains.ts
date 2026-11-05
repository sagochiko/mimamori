// Official domains of the brands that scam messages pretend to be, and where each one is confirmed.
// A host matches when it equals the domain or ends with "." + domain. The source is the brand's own
// site served from that domain (checked on 2026-11-03), or the registry rule for go.jp and lg.jp.
// A host here adds no domain sign (look-alike, odd shape, brand mismatch); the text is still
// checked. Add only domains the brand itself runs. Where anyone can get an address or a page on
// the domain, list it in FREE_MAIL_DOMAINS or USER_CONTENT_HOSTS too.

export interface OfficialDomain {
  domain: string;
  brand: string;
  source: string;
}

const JPRS_RULES = "https://jprs.jp/about/jp-dom/spec/";

export const OFFICIAL_DOMAINS: readonly OfficialDomain[] = [
  { domain: "amazon.co.jp", brand: "amazon", source: "https://www.amazon.co.jp/" },
  { domain: "amazon.jp", brand: "amazon", source: "https://www.amazon.jp/" },
  { domain: "amazon.com", brand: "amazon", source: "https://www.amazon.com/" },
  { domain: "apple.com", brand: "apple", source: "https://www.apple.com/" },
  { domain: "apple.co", brand: "apple", source: "https://apple.co/ (redirects to www.apple.com)" },
  { domain: "icloud.com", brand: "apple", source: "https://www.icloud.com/" },
  { domain: "me.com", brand: "apple", source: "https://www.me.com/ (redirects to www.icloud.com)" },
  { domain: "docomo.ne.jp", brand: "docomo", source: "https://www.docomo.ne.jp/" },
  {
    domain: "nttdocomo.co.jp",
    brand: "docomo",
    source: "https://www.nttdocomo.co.jp/ (redirects to www.docomo.ne.jp)",
  },
  { domain: "au.com", brand: "au", source: "https://www.au.com/" },
  { domain: "kddi.com", brand: "au", source: "https://www.kddi.com/" },
  { domain: "uqwimax.jp", brand: "au", source: "https://www.uqwimax.jp/" },
  { domain: "softbank.jp", brand: "softbank", source: "https://www.softbank.jp/" },
  { domain: "ymobile.jp", brand: "softbank", source: "https://www.ymobile.jp/" },
  { domain: "rakuten.co.jp", brand: "rakuten", source: "https://www.rakuten.co.jp/" },
  { domain: "rakuten-card.co.jp", brand: "rakuten", source: "https://www.rakuten-card.co.jp/" },
  { domain: "rakuten-bank.co.jp", brand: "rakuten", source: "https://www.rakuten-bank.co.jp/" },
  { domain: "rakuten-sec.co.jp", brand: "rakuten", source: "https://www.rakuten-sec.co.jp/" },
  { domain: "japanpost.jp", brand: "japanpost", source: "https://www.post.japanpost.jp/" },
  { domain: "kuronekoyamato.co.jp", brand: "yamato", source: "https://www.kuronekoyamato.co.jp/" },
  { domain: "yamato-hd.co.jp", brand: "yamato", source: "https://www.yamato-hd.co.jp/" },
  { domain: "sagawa-exp.co.jp", brand: "sagawa", source: "https://www.sagawa-exp.co.jp/" },
  { domain: "mufg.jp", brand: "mufg", source: "https://www.bk.mufg.jp/" },
  { domain: "smbc.co.jp", brand: "smbc", source: "https://www.smbc.co.jp/" },
  { domain: "smbc-card.com", brand: "smbc", source: "https://www.smbc-card.com/" },
  { domain: "mizuhobank.co.jp", brand: "mizuho", source: "https://www.mizuhobank.co.jp/" },
  { domain: "resonabank.co.jp", brand: "resona", source: "https://www.resonabank.co.jp/" },
  { domain: "paypay.ne.jp", brand: "paypay", source: "https://paypay.ne.jp/" },
  { domain: "paypay-bank.co.jp", brand: "paypay", source: "https://www.paypay-bank.co.jp/" },
  { domain: "paypay-card.co.jp", brand: "paypay", source: "https://www.paypay-card.co.jp/" },
  { domain: "aeon.co.jp", brand: "aeon", source: "https://www.aeon.co.jp/" },
  { domain: "aeonbank.co.jp", brand: "aeon", source: "https://www.aeonbank.co.jp/" },
  { domain: "mercari.com", brand: "mercari", source: "https://jp.mercari.com/" },
  { domain: "jcb.co.jp", brand: "jcb", source: "https://www.jcb.co.jp/" },
  { domain: "saisoncard.co.jp", brand: "saison", source: "https://www.saisoncard.co.jp/" },
  { domain: "ntt-east.co.jp", brand: "ntt", source: "https://www.ntt-east.co.jp/" },
  { domain: "ntt-west.co.jp", brand: "ntt", source: "https://www.ntt-west.co.jp/" },
  { domain: "line.me", brand: "line", source: "https://www.line.me/" },
  { domain: "google.com", brand: "google", source: "https://www.google.com/" },
  { domain: "yahoo.co.jp", brand: "yahoo", source: "https://www.yahoo.co.jp/" },
  { domain: "antiphishing.jp", brand: "antiphishing", source: "https://www.antiphishing.jp/" },
  // Only government bodies can register go.jp, and only local governments lg.jp (JPRS rules).
  // The police (npa.go.jp, keishicho.metro.tokyo.lg.jp), IPA and the consumer centre are under these.
  { domain: "go.jp", brand: "government", source: JPRS_RULES },
  { domain: "lg.jp", brand: "government", source: JPRS_RULES },
];

// Names that scam domains borrow. A host imitates a brand when one of its parts (split by "." and
// "-") is the name, starts with the name (5 letters or more), or is one letter off a name in
// FUZZY_NAMES. Shorter names must match a whole part, so "au" does not hit "audio". Only a few names
// get the one-letter rule: "mizuho" and "paypay" are one letter off other real companies.
export const BRAND_NAMES: Readonly<Record<string, readonly string[]>> = {
  amazon: ["amazon"],
  apple: ["apple", "appleid", "icloud", "itunes"],
  docomo: ["docomo"],
  au: ["au", "kddi"],
  softbank: ["softbank", "ymobile"],
  rakuten: ["rakuten"],
  japanpost: ["japanpost", "jppost", "jpost", "yubin", "yucho"],
  yamato: ["yamato", "kuroneko"],
  sagawa: ["sagawa"],
  mufg: ["mufg"],
  smbc: ["smbc"],
  mizuho: ["mizuho"],
  resona: ["resona"],
  paypay: ["paypay"],
  aeon: ["aeon"],
  mercari: ["mercari"],
  jcb: ["jcb"],
  saison: ["saison"],
  line: ["line"],
  government: ["npa", "nta", "keishicho", "nenkin", "mynumber"],
};

const FUZZY_NAMES: ReadonlySet<string> = new Set(["amazon", "rakuten", "docomo", "icloud", "mercari", "softbank"]);

// Brand names as they appear in Japanese text, for "the text names a brand but links elsewhere".
export const BRAND_WORDS: Readonly<Record<string, readonly string[]>> = {
  amazon: ["amazon", "アマゾン"],
  apple: ["apple", "アップル", "icloud", "apple id"],
  docomo: ["docomo", "ドコモ"],
  au: ["kddi", "auお客さまサポート", "au pay"],
  softbank: ["softbank", "ソフトバンク", "ワイモバイル"],
  rakuten: ["楽天", "rakuten"],
  japanpost: ["日本郵便", "郵便局", "ゆうちょ", "japan post"],
  yamato: ["ヤマト運輸", "クロネコ"],
  sagawa: ["佐川急便"],
  mufg: ["三菱ufj"],
  smbc: ["三井住友"],
  mizuho: ["みずほ"],
  resona: ["りそな"],
  paypay: ["paypay"],
  aeon: ["イオン"],
  mercari: ["メルカリ", "mercari"],
  jcb: ["jcb"],
  saison: ["セゾン"],
  government: ["国税庁", "警察庁", "警視庁", "厚生労働省", "年金機構"],
};

// Mail domains where anyone can get an address. As the sender, or an address in the text, they say
// nothing about who wrote the message. Matched exactly: email.apple.com is still Apple's.
export const FREE_MAIL_DOMAINS: ReadonlySet<string> = new Set([
  "gmail.com",
  "googlemail.com",
  "icloud.com",
  "me.com",
  "mac.com",
  "yahoo.co.jp",
  "ymail.ne.jp",
  "outlook.com",
  "outlook.jp",
  "hotmail.com",
  "hotmail.co.jp",
  "live.jp",
  "docomo.ne.jp",
  "ezweb.ne.jp",
  "au.com",
  "softbank.ne.jp",
  "i.softbank.jp",
  "ymobile.ne.jp",
]);

// Hosts (and their subdomains) on a brand's domain where anyone can put up a page, a form, or a
// LINE account. A link there is not the brand speaking.
export const USER_CONTENT_HOSTS: readonly string[] = [
  "sites.google.com",
  "docs.google.com",
  "drive.google.com",
  "groups.google.com",
  "script.google.com",
  "line.me",
  "chiebukuro.yahoo.co.jp",
];

// Paths on an official host where anyone can share a file, an album, or a note.
export const USER_CONTENT_PATHS: Readonly<Record<string, readonly string[]>> = {
  "www.icloud.com": [
    "/iclouddrive/",
    "/sharedalbum/",
    "/photos/",
    "/notes/",
    "/pages/",
    "/numbers/",
    "/keynote/",
    "/attachment/",
  ],
};

/**
 * official: the brand speaks from this host. shared: the brand runs it, but anyone can get an
 * address or a page there. other: neither. brand is the domain's owner, for official and shared.
 */
export type HostTrust = { trust: "official" | "shared" | "other"; brand: string | null };

/**
 * asAddress: the host is a mail address's domain. path: the link's path, when it is a link.
 * forceShared: the link only passes the reader on to another URL (a redirect), so anyone can make it.
 * It applies only to an official brand's host (google.com/url): it takes away "the brand speaks
 * here". Any other host stays "other", so its own look-alike and odd shape are still checked; a
 * URL in the query must not hide them.
 */
export function trustOf(host: string, asAddress: boolean, path = "", forceShared = false): HostTrust {
  const h = normalizeHost(host);
  const brand = officialBrandOf(h);
  const p = path.toLowerCase();
  const shared =
    (forceShared && brand !== null) ||
    (asAddress && FREE_MAIL_DOMAINS.has(h)) ||
    USER_CONTENT_HOSTS.some((u) => h === u || h.endsWith(`.${u}`)) ||
    (USER_CONTENT_PATHS[h] ?? []).some((prefix) => p.startsWith(prefix));
  if (shared) return { trust: "shared", brand };
  return brand ? { trust: "official", brand } : { trust: "other", brand: null };
}

export function normalizeHost(host: string): string {
  return host.normalize("NFKC").toLowerCase().replace(/\.$/, "");
}

/** The brand whose official domain this host belongs to, or null. */
export function officialBrandOf(host: string): string | null {
  const h = normalizeHost(host);
  for (const entry of OFFICIAL_DOMAINS) {
    if (h === entry.domain || h.endsWith(`.${entry.domain}`)) return entry.brand;
  }
  return null;
}

// Letters that scam domains swap in: amaz0n, app1e, arnazon.
function unLeet(part: string): string {
  return part
    .replace(/0/g, "o")
    .replace(/1/g, "l")
    .replace(/3/g, "e")
    .replace(/5/g, "s")
    .replace(/rn/g, "m")
    .replace(/vv/g, "w");
}

function withinOneEdit(a: string, b: string): boolean {
  if (a === b) return true;
  if (Math.abs(a.length - b.length) > 1) return false;
  let i = 0;
  let j = 0;
  let edits = 0;
  while (i < a.length && j < b.length) {
    if (a[i] === b[j]) {
      i++;
      j++;
      continue;
    }
    if (++edits > 1) return false;
    if (a.length > b.length) i++;
    else if (b.length > a.length) j++;
    else {
      i++;
      j++;
    }
  }
  return edits + (a.length - i) + (b.length - j) <= 1;
}

/** The brand this non-official host imitates, or null. Official hosts always return null. */
export function imitatedBrandOf(host: string): string | null {
  const h = normalizeHost(host);
  if (officialBrandOf(h)) return null;
  const parts = h.split(/[.-]/).filter(Boolean).map(unLeet);
  for (const [brand, names] of Object.entries(BRAND_NAMES)) {
    for (const name of names) {
      for (const part of parts) {
        if (part === name) return brand;
        if (name.length >= 5 && part.startsWith(name)) return brand;
        if (FUZZY_NAMES.has(name) && withinOneEdit(part, name)) return brand;
      }
    }
  }
  return null;
}
