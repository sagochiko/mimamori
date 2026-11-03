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

describe("official domains", () => {
  it("adds no domain sign for a government page that only warns", () => {
    const result = judge({
      source: "page",
      url: "https://www.npa.go.jp/example/warning.html",
      domain: "www.npa.go.jp",
      text: "警察官をかたる電話に気をつけましょう。不審な電話は一度切って、警察相談専用電話 #9110 に相談してください。",
    });
    expect(result.level).toBeNull();
    expect(result.confident).toBe(false);
  });

  // The rules cannot tell a quote from the script itself. Not confident, so Claude may lower it.
  it("still raises an official page that carries the fake-police script, without being confident", () => {
    const result = judge({
      source: "page",
      url: "https://www.npa.go.jp/example/warning.html",
      domain: "www.npa.go.jp",
      text: "警察官をかたり「あなたの口座が犯罪に使われている」「誰にも言わないで」と言う電話は詐欺です。",
    });
    expect(result.level).toBe(1);
    expect(result.confident).toBe(false);
  });

  it("checks the text when the only link in it is official", () => {
    const result = judge({
      source: "sms",
      sender: "+819000000000",
      text: "この警告は誤りです。家族に知らせないでください。詳しくは https://www.npa.go.jp/ をご覧ください",
    });
    expect(result.level).toBe(1);
  });

  it("checks the text when the sender claims an official domain", () => {
    const result = judge({
      source: "gmail",
      sender: "info@amazon.co.jp",
      text: "あなたの口座が犯罪に使われています。潔白を証明するため送金してください。",
    });
    expect(result.level).toBe(1);
  });

  it("checks the fake-police script even with a LINE link", () => {
    const result = judge({
      source: "consult",
      text: "警察から電話があって、口座が犯罪に使われてるって。誰にも言わないで、line.me/ti/p/example で追加してって",
    });
    expect(result.level).toBe(1);
  });

  it.each([
    ["icloud.com", "keisatsu-example@icloud.com"],
    ["yahoo.co.jp", "someone-example@yahoo.co.jp"],
  ])("does not treat a free mail address at %s as the brand itself", (_, sender) => {
    const result = judge({
      source: "gmail",
      sender,
      text: "警視庁です。あなたの口座が犯罪に使われています。逮捕状が出ています。暗証番号を返信してください。",
    });
    expect(result.level).toBe(1);
  });

  it("does not treat a page anyone can make on sites.google.com as official", () => {
    const result = judge({
      source: "page",
      url: "https://sites.google.com/view/example",
      domain: "sites.google.com",
      text: "お使いのiPhoneはウイルスに感染しています。今すぐサポートセンター 050-0000-0000 に電話してください。",
    });
    expect(result.level).toBe(1);
  });

  it("counts a delivery notice that links to a user page on an official domain", () => {
    const result = judge({
      source: "sms",
      text: "お荷物のお届けにあがりましたが不在の為持ち帰りました。 https://sites.google.com/view/redelivery-example",
    });
    expect(result.level).not.toBeNull();
  });

  it("does not call LINE's own domain a look-alike, nor official", () => {
    const result = judge({ source: "dns", domain: "line.me" });
    expect(result.level).toBeNull();
    expect(result.reasons.join(" ")).not.toContain("公式");
  });
});

describe("confident needs a sign that genuine messages do not give", () => {
  it.each([
    ["a brand's own short link with a delivery word", { source: "sms", sender: "+819000000000", text: "Amazon: ご注文の商品のお届け予定は本日です。配送状況の確認 https://amzn-short.example/d/abc123" }],
    ["a brand's own short link with points", { source: "sms", text: "楽天市場: ポイントの有効期限が近づいています。こちらから確認 https://r10-short.example/abcd" }],
    ["a code from abroad that says to ignore it", { source: "sms", sender: "+447000000000", text: "Your verification code is 123456. 心当たりがない場合、この通知は無視してください。" }],
    ["a family surprise", { source: "sms", text: "お母さんの誕生日のサプライズ、家族には内緒でね" }],
    ["a shop's mail", { source: "gmail", sender: "news@shop.example", text: "家族に内緒のごほうびスイーツ、本日限定" }],
    ["a news page that quotes the fake-police script", { source: "page", url: "https://news.example/x.html", text: "警察官をかたり「あなたの口座が犯罪に使われている」「誰にも言わないで」と言う電話が相次いでいます" }],
  ] as [string, RuleInput][])("is not confident for %s", (_, input) => {
    expect(judge(input).confident).toBe(false);
  });

  it("counts one phrase that two rules match as one sign", () => {
    const result = judge({ source: "sms", sender: "+639000000000", text: "このことは家族に言わないでください。" });
    expect(result.level).toBe(1);
    expect(result.confident).toBe(false);
  });

  it("does not count 'ignore this notice' without a link or a number to call", () => {
    const result = judge({ source: "sms", sender: "+819000000000", text: "認証コード: 123456 心当たりがない場合、この通知は無視してください。" });
    expect(result.level).toBeNull();
  });

  it("counts 'ignore this notice' when it comes with a link", () => {
    const result = judge({
      source: "sms",
      text: "心当たりがない場合、この通知は無視してください。ご確認はこちら https://account-check.example/",
    });
    expect(result.level).not.toBeNull();
  });
});

describe("verification codes", () => {
  it.each([
    "認証コード 123456 を入力してください",
    "認証コード 123456 を入力してください。このコードは他人に言わないでください。",
    "【ゆうちょ銀行】ワンタイムパスワード 123456 を画面に入力してください。銀行が電話でこの番号を聞くことはありません。",
  ])("leaves a code to type in at null: %s", (text) => {
    const result = judge({ source: "sms", text });
    expect(result.level).toBeNull();
    expect(result.confident).toBe(false);
  });

  it("still flags a message that asks to send the code back", () => {
    const result = judge({ source: "sms", text: "認証コード 123456 をこのメッセージに返信して教えてください" });
    expect(result.level).not.toBeNull();
  });
});

describe("telling someone not to tell the family", () => {
  it.each([
    "このことはご家族には内緒にしてください",
    "息子さんには絶対に言わないでください",
    "家族にも知らせないようにお願いします",
  ])("raises %s", (text) => {
    expect(judge({ source: "consult", text }).level).toBe(1);
  });

  it.each([
    ["page", "子どもの秘密基地を作ろう。段ボールで簡単にできます"],
    ["gmail", "家族に内緒のごほうびスイーツ、本日限定"],
    ["sms", "お母さんの誕生日のサプライズ、家族には内緒でね"],
  ] as const)("does not raise an unrelated %s", (source, text) => {
    expect(judge({ source, text }).level).toBeNull();
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
