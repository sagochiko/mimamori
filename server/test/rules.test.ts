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

  // The rules cannot tell a quote from the script itself. An official sender or link keeps any
  // level from being confident, so a genuine warning is never sent to the junk folder; Claude may
  // lower it. The trade-off: a scam that adds an official link avoids the junk folder too.
  it.each([
    ["a police page quoting 'tell no one'", { source: "page", url: "https://www.npa.go.jp/example/warning.html", domain: "www.npa.go.jp", text: "警察官をかたり「あなたの口座が犯罪に使われている」「誰にも言わないで」と言う電話は詐欺です。" }],
    ["a police page quoting 'do not consult the family'", { source: "page", url: "https://www.npa.go.jp/example/warning.html", domain: "www.npa.go.jp", text: "警察官をかたり「あなたの口座が犯罪に使われている」「家族に相談しないで」と言う電話は詐欺です。" }],
    ["a bank's mail quoting 'do not tell the family'", { source: "gmail", sender: "info@rakuten-bank.co.jp", text: "楽天銀行より: 警察官を名乗り「口座が犯罪に使われている」「ご家族には言わないで」と指示する詐欺電話が増えています。" }],
    ["a bank's SMS with its own link", { source: "sms", text: "【ゆうちょ銀行】警察官を名乗り「あなたの口座が犯罪に使われている」「家族に相談しないで」と言う詐欺電話にご注意ください。 https://www.jp-bank.japanpost.jp/" }],
    ["a consumer centre SMS quoting a gift card scam", { source: "sms", text: "【国民生活センター】「ウイルスに感染しました」と表示させ、電子マネーを購入させる詐欺にご注意ください https://www.kokusen.go.jp/" }],
  ] as [string, RuleInput][])("raises %s but is never confident", (_, input) => {
    const result = judge(input);
    expect(result.level).toBe(1);
    expect(result.confident).toBe(false);
  });

  it("stays confident when the brand's domain is only written as a name", () => {
    const result = judge({
      source: "sms",
      sender: "+639000000000",
      text: "【Amazon.co.jp】本日中にお支払い方法を更新しないとアカウントが停止されます https://amazon-pay-update.top/",
    });
    expect(result.level).toBe(1);
    expect(result.confident).toBe(true);
  });

  it("is not confident even for a look-alike when an official link is added (accepted trade-off)", () => {
    const result = judge({
      source: "sms",
      text: "【Amazon】お支払い方法を更新してください https://amazon-pay-update.top/ 公式 https://www.amazon.co.jp/",
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

  it("does not count 'ignore this notice' without a link", () => {
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

describe("a code number in a scam does not lower it", () => {
  it.each([
    ["a code put in front of the script", "【警視庁】認証コード 1234。あなたの口座が犯罪に使われています。この件は誰にも言わないでください。至急 03-0000-0000 へお電話ください。"],
    ["a code word and only the digits of a phone number", "【警視庁】あなたの口座が犯罪に使われています。確認番号をお伝えしますので、この件は誰にも言わないでください。至急 03-0000-0000 へお電話ください。"],
    ["'code 0000'", "code 0000 あなたの口座が犯罪に使われています。誰にも言わないでください"],
    ["a code with secrecy and a transfer", "確認コード 4821。家族を含め誰にも言わないで、安全な口座に送金してください。"],
  ])("keeps %s at level 1", (_, text) => {
    expect(judge({ source: "sms", sender: "+819000000000", text }).level).toBe(1);
  });

  it.each([
    ["a code word next to a phone number", "確認番号をお伝えします。この件は誰にも言わないでください。03-0000-0000 へお電話を。"],
    ["a phone number written with long dashes", "【警視庁】確認番号をお伝えします。この件は誰にも言わないでください。03ー0000ー0000 へお電話を。"],
    ["a phone number written with brackets", "【警視庁】確認番号をお伝えします。この件は誰にも言わないでください。03(0000)0000 へお電話を。"],
    ["a code with a transfer", "確認コード 4821。この件は誰にも言わないで、安全な口座に送金してください。"],
    ["a code next to a phone number", "確認コード 4821。この件は誰にも言わないでください。03-0000-0000 へお電話を。"],
  ])("counts the secrecy in %s", (_, text) => {
    expect(judge({ source: "sms", text }).level).toBe(2);
  });

  it("keeps the secrecy reason in a mail with a code", () => {
    const result = judge({
      source: "gmail",
      sender: "keisatsu@police-jp.example",
      text: "警視庁です。確認コード 5821。あなたの口座が犯罪に使われています。誰にも話さないでください。",
    });
    expect(result.level).toBe(1);
    expect(result.reasons).toContain("ほかの人に話さないよう言われている");
  });

  it.each([
    "【三井住友】認証コード 1234。暗証番号を送ってください。至急 03-0000-0000",
    "認証コード 1234 をお電話で入力してください。暗証番号も入力が必要です 0120-000-000",
    "認証コード 1234。暗証番号を入力してください。",
  ])("still counts a request for a PIN next to a code: %s", (text) => {
    expect(judge({ source: "sms", text }).level).toBe(2);
  });
});

describe("genuine code and bank notices", () => {
  it.each([
    ["sms", undefined, "認証コード 123456。このコードはご家族にも教えないでください。"],
    ["sms", undefined, "【〇〇銀行】ワンタイムパスワード 123456。家族にも絶対に教えないでください。"],
    ["gmail", "info@smbc.co.jp", "暗証番号はご家族にも教えないようにしましょう。"],
    ["sms", undefined, "【〇〇銀行】認証コード 123456。心当たりがない場合、このメッセージは無視してください。お問い合わせ 0120-000-000"],
  ] as const)("leaves a %s notice at null", (source, sender, text) => {
    const result = judge({ source, sender, text });
    expect(result.level).toBeNull();
    expect(result.confident).toBe(false);
  });
});

describe("links to pages anyone can make", () => {
  it("counts a delivery notice that links to an Apps Script page", () => {
    expect(judge({ source: "sms", text: "Amazon: お荷物をお届けできませんでした。再配達はこちら https://script.google.com/macros/s/example/exec" }).level).not.toBeNull();
  });

  it("counts a storage warning that links to an iCloud shared file", () => {
    expect(judge({ source: "sms", text: "Apple: iCloudストレージがいっぱいです。こちら https://www.icloud.com/iclouddrive/0example" }).level).not.toBeNull();
  });

  it("looks at where a redirect link goes", () => {
    const result = judge({
      source: "sms",
      text: "Amazon: お荷物をお届けできませんでした。 https://www.google.com/url?q=https://amaz0n-redeliver.top/x",
    });
    expect(result.level).toBe(1);
    expect(result.reasons.join(" ")).toContain("amaz0n-redeliver.top");
    // google.com only passes the reader on here, so it is no official link that would keep this
    // from being confident.
    expect(result.confident).toBe(true);
  });
});

describe("a link that looks like a redirect", () => {
  // Only a redirect on an official brand's host (google.com) stops counting as the brand speaking.
  // Any other host is checked itself, whatever it carries in its query.
  it.each([
    ["a look-alike page with a return URL", { source: "page", url: "https://amazon-co-jp.top/signin?return=https://example.org/" }, 1],
    ["an odd-shaped link with a URL in its query", { source: "sms", text: "ご確認ください https://kakunin-x.top/?u=https://example.org/" }, 2],
    ["a look-alike SMS link with a URL in its query", { source: "sms", text: "【Amazon】お支払い方法を更新しないとアカウントが停止されます https://amazon-pay-update.top/?r=https://example.org/" }, 1],
    ["a look-alike page that carries the bank's own URL", { source: "page", url: "https://smbc-login.top/?back=https://www.smbc.co.jp/", text: "三井住友銀行 ログイン" }, 1],
    ["an IP address link that carries the bank's own URL", { source: "sms", text: "【三井住友】ご利用確認のため至急ログイン http://192.168.10.10/smbc?u=https://www.smbc.co.jp/" }, 1],
  ] as [string, RuleInput, number][])("checks the host of %s", (_, input, level) => {
    expect(judge(input).level).toBe(level);
  });
});

describe("more ways to keep the family out", () => {
  it.each([
    "この件はご家族や友人にも話さないでください。",
    "捜査中のため、ご家族や銀行の方には言わないでください。",
  ])("raises %s", (text) => {
    expect(judge({ source: "sms", text }).level).toBe(1);
  });

  it("raises a message that says this notice is wrong", () => {
    expect(judge({ source: "consult", text: "この通知は誤りです。警察から言われました" }).level).toBe(1);
  });

  it("counts a request to turn this notice off when it comes with a link", () => {
    expect(judge({ source: "sms", text: "この通知をオフにしてください https://x-check.example/" }).level).not.toBeNull();
  });
});

describe("signs that are only weak", () => {
  it("do not join two other signs into one", () => {
    expect(judge({ source: "sms", text: "口座番号を入力で悪用ロック" }).level).toBe(1);
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
