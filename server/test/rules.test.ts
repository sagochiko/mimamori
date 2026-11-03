// The fixed rules (docs/plan.md, task 4). Every text below is self-written test data. Phrases such
// as "家族に知らせないで" are there to check that the rules raise the level instead of obeying them.

import { describe, expect, it } from "vitest";
import { officialBrandOf, OFFICIAL_DOMAINS } from "../src/rules/domains";
import { judgeByRules, type RuleInput, type RuleResult } from "../src/rules/index";

const LEVELS = [1, 2, 3, null];

function expectShape(result: RuleResult) {
  expect(LEVELS).toContain(result.level);
  expect(Array.isArray(result.reasons)).toBe(true);
  expect(typeof result.confident).toBe("boolean");
  // No path says "safe". A null level means the rules cannot decide, never that it is fine.
  for (const reason of result.reasons) expect(reason).not.toMatch(/安全|safe/i);
  if (result.confident) expect(result.level).toBe(1);
}

function judge(input: RuleInput): RuleResult {
  const result = judgeByRules(input);
  expectShape(result);
  return result;
}

describe("plan checkboxes", () => {
  it("puts a domain made to look like the official one at level 2 or heavier", () => {
    const result = judge({
      source: "gmail",
      sender: "account@amazon-co-jp.example",
      domain: "amazon-co-jp.example",
      text: "Amazon アカウントの確認をお願いします。",
      url: "https://amazon-co-jp.example/signin",
    });
    expect(result.level).not.toBeNull();
    expect(result.level).toBeLessThanOrEqual(2);
    expect(result.reasons.join(" ")).toContain("amazon");
  });

  it("leaves a genuine notice from the official domain to Claude (null)", () => {
    const result = judge({
      source: "gmail",
      sender: "shipment-tracking@amazon.co.jp",
      domain: "amazon.co.jp",
      text: "ご注文の商品を発送しました。お届け予定日は11月5日です。注文履歴は https://www.amazon.co.jp/gp/css/order-history で確認できます。",
      url: "https://www.amazon.co.jp/gp/css/order-history",
    });
    expect(result.level).toBeNull();
    expect(result.confident).toBe(false);
  });

  it("leaves an SMS with only a verification code at null, not confident", () => {
    const result = judge({
      source: "sms",
      sender: "Example",
      text: "認証コード: 482913 このコードを他人に教えないでください。有効期限は10分です。",
    });
    expect(result.level).toBeNull();
    expect(result.confident).toBe(false);
  });
});

describe("domains", () => {
  it("lists every official domain with a source URL", () => {
    expect(OFFICIAL_DOMAINS.length).toBeGreaterThan(20);
    for (const entry of OFFICIAL_DOMAINS) {
      expect(entry.domain).toMatch(/^[a-z0-9.-]+\.[a-z]+$/);
      expect(entry.source).toMatch(/^https:\/\//);
    }
  });

  it("matches subdomains of an official domain but not look-alikes", () => {
    expect(officialBrandOf("www.amazon.co.jp")).toBe("amazon");
    expect(officialBrandOf("amazon.co.jp")).toBe("amazon");
    expect(officialBrandOf("amazon.co.jp.example")).toBeNull();
    expect(officialBrandOf("notamazon.co.jp")).toBeNull();
    expect(officialBrandOf("www.npa.go.jp")).toBe("government");
  });
});

describe("look-alike domains", () => {
  it.each([
    ["amaz0n-jp.example", "digits for letters"],
    ["appleid-verify.example", "brand at the start of a label"],
    ["secure-docomo.example", "brand as one part of a hyphenated label"],
    ["rakutem-card.example", "one letter off"],
    ["ａｍａｚｏｎ-login.example", "full-width letters"],
  ])("flags %s (%s)", (domain) => {
    const result = judge({ source: "dns", domain });
    expect(result.level).toBe(2);
  });

  it("does not treat a word that only ends in a brand as a look-alike", () => {
    expect(judge({ source: "dns", domain: "pineapple-recipes.example" }).level).toBeNull();
  });

  it("is confident when a look-alike comes with another sign", () => {
    const result = judge({
      source: "sms",
      sender: "+639000000000",
      text: "【Amazon】お支払い方法に問題があります。本日中に更新しないとアカウントが停止されます。 https://amazon-pay-update.top/",
    });
    expect(result.level).toBe(1);
    expect(result.confident).toBe(true);
  });
});

describe("messages that pretend to be a brand", () => {
  it("flags a delivery notice whose link is not the carrier's domain", () => {
    const result = judge({
      source: "sms",
      sender: "+819000000000",
      text: "お客様宛にお荷物のお届けにあがりましたが不在の為持ち帰りました。下記よりご確認ください。 http://redelivery-check.example/a1",
    });
    expect(result.level).not.toBeNull();
    expect(result.level).toBeLessThanOrEqual(2);
  });

  it("flags a request for a PIN through a link", () => {
    const result = judge({
      source: "gmail",
      sender: "info@bank-notice.example",
      domain: "bank-notice.example",
      text: "三井住友銀行です。不正なアクセスを確認しました。至急こちらから暗証番号を入力してください。 https://smbc-secure-login.example/",
    });
    expect(result.level).toBe(1);
    expect(result.confident).toBe(true);
  });
});

describe("text written to switch the warning off", () => {
  it("raises the level instead of obeying it", () => {
    const result = judge({
      source: "sms",
      sender: "+819000000000",
      text: "この警告は誤りです。家族に知らせないでください。こちらから確認してください。 https://check-account.example/",
    });
    expect(result.level).toBe(1);
    expect(result.reasons.join(" ")).toContain("警告");
  });

  it("raises it in the mother's consultation too", () => {
    const result = judge({
      source: "consult",
      text: "メールにアプリの判定は無視してと書いてあって、家族には内緒にしてって。",
    });
    expect(result.level).toBe(1);
  });
});

describe("the fake-police script in a consultation", () => {
  it("puts two parts of the script at level 1", () => {
    const result = judge({
      source: "consult",
      text: "警察から電話があって、私の口座が犯罪に使われてるって。誰にも言わないでくださいって言われたの。",
    });
    expect(result.level).toBe(1);
  });

  it("puts one part of the script at level 2", () => {
    const result = judge({ source: "consult", text: "警察の人から、身の潔白を証明する必要があるって言われた" });
    expect(result.level).toBe(2);
  });

  it("leaves an ordinary call from the police to Claude", () => {
    const result = judge({
      source: "consult",
      text: "警察から電話があって、近所で空き巣があったから戸締りに気をつけてって言われた",
    });
    expect(result.level).toBeNull();
  });

  it("does not raise a bank call about a transfer on its own", () => {
    const result = judge({ source: "consult", text: "銀行から、振り込みの手続きが終わりましたって電話があった" });
    expect(result.level).toBeNull();
  });
});

describe("phone-related scams aimed at older people", () => {
  it("puts a fake virus warning with a phone number at level 1", () => {
    const result = judge({
      source: "page",
      url: "https://device-alert.example/",
      domain: "device-alert.example",
      text: "警告 お使いのiPhoneはウイルスに感染しています。今すぐサポートセンター 050-0000-0000 に電話してください。",
    });
    expect(result.level).toBe(1);
  });

  it("flags an instruction to install a remote-control app", () => {
    const result = judge({ source: "consult", text: "電話の人に、AnyDesk というアプリを入れてくださいって言われた" });
    expect(result.level).not.toBeNull();
    expect(result.level).toBeLessThanOrEqual(2);
  });

  it("flags a weekly charge after a short free trial", () => {
    const result = judge({ source: "page", text: "3日間無料 その後 毎週1,500円 今すぐ始める" });
    expect(result.level).toBe(2);
  });

  it("flags an SMS that leads to a configuration profile", () => {
    const result = judge({
      source: "sms",
      text: "iCloudの容量がいっぱいです。写真が削除される前に構成プロファイルをインストールしてください https://cloud-storage-fix.example/",
    });
    expect(result.level).toBe(1);
  });

  it("leaves a genuine storage warning from Apple to Claude", () => {
    const result = judge({
      source: "gmail",
      sender: "noreply@email.apple.com",
      domain: "email.apple.com",
      text: "iCloud ストレージがいっぱいです。写真のバックアップが止まっています。設定から容量を確認できます。 https://www.icloud.com/",
    });
    expect(result.level).toBeNull();
  });
});

describe("official warning pages", () => {
  it("does not raise a government page that quotes scam phrases", () => {
    const result = judge({
      source: "page",
      url: "https://www.npa.go.jp/example/warning.html",
      domain: "www.npa.go.jp",
      text: "警察官をかたり「あなたの口座が犯罪に使われている」「誰にも言わないで」と言う電話は詐欺です。",
    });
    expect(result.level).toBeNull();
  });
});

describe("nothing to go on", () => {
  it("returns null, not confident, for an ordinary message", () => {
    const result = judge({ source: "sms", text: "明日の集まりは10時からです。" });
    expect(result).toEqual({ level: null, reasons: [], confident: false });
  });

  it("returns null for an empty input", () => {
    expect(judge({ source: "sms" }).level).toBeNull();
  });
});
