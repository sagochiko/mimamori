// src/summary.ts: what counts as cutting her words or the received text out into the family's line.

import { describe, expect, it } from "vitest";
import { carriesContact, ownLines, QUOTE_RUN, quotes, repeats } from "../src/summary";

describe("repeats", () => {
  it("counts eight characters in a row from the source", () => {
    expect(QUOTE_RUN).toBe(8);
    expect(repeats("口座が凍結されると急がせている", ["口座が凍結されるって電話で言われた"])).toBe(true);
  });

  it("counts exactly eight, not seven", () => {
    expect(repeats("あいうえおかきく", ["xあいうえおかきくx"])).toBe(true);
    expect(repeats("あいうえおかき", ["xあいうえおかきx"])).toBe(false);
    expect(repeats("あいうえおかきZ", ["xあいうえおかきくx"])).toBe(false);
  });

  it("is not fooled by a comma or a middle dot put in between, on either side", () => {
    expect(repeats("口座が、凍結される相談", ["口座が凍結されると言われた"])).toBe(true);
    expect(repeats("口座が凍結・される相談", ["口座が凍結されると言われた"])).toBe(true);
    expect(repeats("口座が凍結される相談", ["口座が、凍結されるって"])).toBe(true);
    expect(repeats("口座が凍結される相談", ["口座が 凍結 されるって"])).toBe(true);
  });

  it("reads full-width and half-width letters, and upper and lower case, as the same", () => {
    expect(repeats("ATMで振り込んでと言われた", ["ＡＴＭで振り込んでください"])).toBe(true);
    expect(repeats("atmで振り込んでの話", ["ATMで振り込んでください"])).toBe(true);
  });

  it("does not count a line of its own words", () => {
    expect(repeats("お金の話で急がせている", ["口座が凍結されるって電話で言われた"])).toBe(false);
    expect(repeats("", ["口座が凍結されるって"])).toBe(false);
  });
});

describe("quotes", () => {
  it("also counts anything in quotation brackets", () => {
    expect(quotes("「至急」と急がせる", ["全く別の文"])).toBe(true);
    expect(quotes("『重要』と書いてある", ["全く別の文"])).toBe(true);
    expect(quotes("お金の話で急がせている", ["全く別の文"])).toBe(false);
  });
});

describe("ownLines", () => {
  const said = ["口座が凍結されるって電話で言われて、どうしたらいいのか分からない"];

  it("keeps the fixed lines, drops the lines that quote, and falls back when none is left", () => {
    expect(ownLines(["口座が凍結されると急がせている", "お金の話で急がせている"], [], said, ["決まった1行"])).toEqual([
      "お金の話で急がせている",
    ]);
    expect(ownLines(["口座が凍結されると急がせている"], [], said, ["決まった1行"])).toEqual(["決まった1行"]);
    expect(ownLines(["口座が凍結されると急がせている"], ["口座が凍結されると急がせている"], said, [])).toEqual([
      "口座が凍結されると急がせている",
    ]);
  });
});

// A reason with a number to call or a place to open does not go to the mother (#53, review 4 of PR #41).
describe("carriesContact", () => {
  it.each([
    "公式窓口 0120-000-000 に電話して確かめて",
    "０１２０－０００－０００ に電話させる",
    "0120 000 000 へ折り返させる",
    "03(1234)5678 にかけさせる",
    "090ー1234ー5678 へ連絡させる",
    "+81 90 1234 5678 へ連絡させる",
    "https://bank-check.example/ を開かせる",
    "ｈｔｔｐｓ：／／bank-check.example を開かせる",
    "bank-check.example にアクセスさせる",
    "ＢＡＮＫ－ＣＨＥＣＫ．ＥＸＡＭＰＬＥ を開かせる",
    "www.example.jp で手続きさせる",
    "support@bank-check.example に返信させる",
  ])("is true for %s", (line) => {
    expect(carriesContact(line)).toBe(true);
  });

  it.each([
    "知らない番号に電話させようとしている",
    "2026年11月6日に届いた",
    "100,000円を振り込ませる",
    "110番を名乗る",
    "送り主のドメインが公式と違う",
    "家族に確かめるまで待って",
  ])("is false for %s", (line) => {
    expect(carriesContact(line)).toBe(false);
  });
});
