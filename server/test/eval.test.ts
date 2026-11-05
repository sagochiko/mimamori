// The pure parts of eval/: reading cases, splitting patterns, and scoring a run. The parts that touch
// files are tested on temporary folders in eval/test/ (run with `npx tsx --test`).

import { http, HttpResponse } from "msw";
import { describe, expect, it } from "vitest";
import { parseCases, type EvalCase } from "../../eval/lib/cases";
import {
  claudeJudge,
  type ConsultJudge,
  type Judge,
  JudgeUnavailableError,
  loadConsultJudge,
  loadJudge,
  unavailableConsultJudge,
  unavailableJudge,
} from "../../eval/lib/judge";
import { countRunsOn, judgeCases, percentile, resultsRow, scoreRun, toRuleInput } from "../../eval/lib/score";
import { planSplit, type PatternFile } from "../../eval/lib/split-plan";
import type { ClaudeJudgment } from "../src/claude";
import type { ClaudeConsult } from "../src/consult-judge";
import { judgeByRules, type RuleResult } from "../src/rules";
import { network } from "./network";

function line(overrides: Partial<EvalCase> = {}): string {
  return JSON.stringify({
    id: "sms-x-1",
    source: "sms",
    sender: null,
    domain: null,
    text: "test",
    url: null,
    expected_level: 1,
    is_scam: true,
    note: "self-written",
    ...overrides,
  });
}

describe("parseCases", () => {
  it("reads one case per line and skips blank lines", () => {
    const cases = parseCases(`${line()}\n\n${line({ id: "sms-x-2" })}\n`, "sms-x.jsonl");
    expect(cases.map((c) => c.id)).toEqual(["sms-x-1", "sms-x-2"]);
  });

  it.each([
    [{ expected_level: "safe" }, "expected_level"],
    [{ expected_level: 0 }, "expected_level"],
    [{ source: "fax" }, "source"],
    [{ is_scam: "yes" }, "is_scam"],
    [{ note: "" }, "note"],
    [{ id: "" }, "id"],
    [{ text: 3 }, "text"],
  ])("refuses %j", (overrides, field) => {
    expect(() => parseCases(line(overrides as Partial<EvalCase>), "bad.jsonl")).toThrow(field);
  });

  it("names the file and line of broken JSON", () => {
    expect(() => parseCases(`${line()}\n{oops`, "bad.jsonl")).toThrow("bad.jsonl:2");
  });
});

describe("planSplit", () => {
  const file = (name: string, count: number, source = "sms", isScam = true): PatternFile => ({
    name,
    source: source as PatternFile["source"],
    isScam,
    count,
  });

  it("never puts one pattern file on both sides", () => {
    const plan = planSplit([file("sms-scam-a.jsonl", 4), file("sms-scam-b.jsonl", 4)]);
    const sets = plan.assignments.map((a) => a.set).sort();
    expect(sets).toEqual(["dev", "holdout"]);
  });

  it("splits each path and scam or genuine group into halves as equal as possible", () => {
    const files = [
      file("sms-scam-a.jsonl", 5),
      file("sms-scam-b.jsonl", 3),
      file("sms-scam-c.jsonl", 2),
      file("sms-genuine-a.jsonl", 6, "sms", false),
      file("sms-genuine-b.jsonl", 1, "sms", false),
      file("sms-genuine-c.jsonl", 5, "sms", false),
      file("page-scam-a.jsonl", 7, "page"),
    ];
    const plan = planSplit(files);
    const group = (key: string) => plan.groups.find((g) => g.key === key);
    expect(group("sms/scam")).toMatchObject({ dev: { cases: 5 }, holdout: { cases: 5 } });
    expect([group("sms/genuine")?.dev.cases, group("sms/genuine")?.holdout.cases].sort()).toEqual([6, 6]);
    // One file cannot be halved; the larger side goes to the holdout so its denominator is not empty.
    expect(group("page/scam")).toMatchObject({ dev: { cases: 0 }, holdout: { cases: 7 } });
  });

  it("gives the holdout the larger half when the counts are odd", () => {
    const plan = planSplit([file("a.jsonl", 3), file("b.jsonl", 2)]);
    expect(plan.groups[0]).toMatchObject({ dev: { cases: 2 }, holdout: { cases: 3 } });
  });

  it("spreads injection patterns across both sides when the counts allow it", () => {
    const plan = planSplit([
      file("sms-scam-a.jsonl", 2),
      file("sms-scam-b.jsonl", 2),
      file("sms-injection-a.jsonl", 2),
      file("sms-injection-b.jsonl", 2),
    ]);
    // 4 and 4 either way; the tie goes to the split with injection cases on both sides.
    expect(plan.groups[0]).toMatchObject({ dev: { cases: 4, injection: 2 }, holdout: { cases: 4, injection: 2 } });
  });

  it("gives the same answer whatever order the files come in", () => {
    const files = Array.from({ length: 9 }, (_, i) => file(`sms-scam-${i}.jsonl`, (i % 4) + 1));
    const a = planSplit(files);
    const b = planSplit([...files].reverse());
    expect(a.assignments).toEqual(b.assignments);
  });

  it("still splits groups too large to try every combination", () => {
    const files = Array.from({ length: 24 }, (_, i) => file(`sms-scam-${i}.jsonl`, 2));
    const plan = planSplit(files);
    expect(plan.groups[0]).toMatchObject({ dev: { cases: 24 }, holdout: { cases: 24 } });
  });
});

describe("scoreRun", () => {
  const scored = (source: EvalCase["source"], isScam: boolean, level: 1 | 2 | 3 | null, ms = 1) => ({
    id: `${source}-${isScam}-${level}-${ms}`,
    source,
    is_scam: isScam,
    expected_level: isScam ? (1 as const) : null,
    level,
    latency_ms: ms,
  });

  it("counts misses, false alarms, and genuine cases put at level 1", () => {
    const out = scoreRun([
      scored("sms", true, 1),
      scored("sms", true, 2),
      scored("sms", true, null), // miss: the rules could not decide
      scored("sms", true, 3), // miss: level 3 does not reach the family
      scored("sms", false, null),
      scored("sms", false, 3),
      scored("sms", false, 2), // false alarm
      scored("gmail", false, 1), // false alarm at level 1
    ]);
    expect(out).toMatchObject({
      misses: 2,
      miss_rate: 0.5,
      false_alarms: 2,
      false_alarm_rate: 0.5,
      genuine_at_level1: 1,
      unneeded_family_pushes: 2,
    });
    expect(out.by_source.sms).toMatchObject({ n: 7, scam: 4, genuine: 3, misses: 2, false_alarms: 1 });
    expect(out.by_source.gmail).toMatchObject({ n: 1, scam: 0, miss_rate: null, genuine_at_level1: 1 });
  });

  // #109: a genuine consultation on a topic the AI does not guide goes to the family by design
  // (decidePlan). It stays a false alarm, since the family was told, and is also counted on its own.
  it("counts the false alarms on topics the AI does not guide apart, inside false_alarms", () => {
    const unguided = (isScam: boolean, level: 1 | 2 | 3 | null) => ({
      ...scored("consult", isScam, level),
      unguided_topic: true,
    });
    const out = scoreRun([
      unguided(false, 2), // a false alarm, and one on such a topic
      unguided(true, 2), // a scam: no false alarm at all
      scored("consult", false, 2), // a false alarm Claude made
      { ...scored("consult", false, 3), unguided_topic: false },
      scored("sms", false, 2),
    ]);
    expect(out).toMatchObject({ false_alarms: 3, false_alarms_unguided: 1 });
    expect(out.by_source.consult).toMatchObject({ false_alarms: 2, false_alarms_unguided: 1 });
    expect(out.by_source.sms).toMatchObject({ false_alarms: 1, false_alarms_unguided: 0 });
  });

  it("reports the median and the slowest tenth of the latency", () => {
    const cases = Array.from({ length: 10 }, (_, i) => scored("sms", true, 1, i + 1));
    const out = scoreRun(cases);
    expect(out.p50_latency_ms).toBe(5);
    expect(out.p90_latency_ms).toBe(9);
  });

  it("uses nearest-rank percentiles", () => {
    expect(percentile([3, 1, 2], 50)).toBe(2);
    expect(percentile([], 50)).toBeNull();
    expect(percentile([7], 90)).toBe(7);
  });
});

describe("records", () => {
  it("counts only rules+claude runs on the dev set for the daily budget", () => {
    const lines = [
      { ts: "2026-11-03T09:00:00+09:00", set: "dev", mode: "rules+claude" },
      { ts: "2026-11-03T10:00:00+09:00", set: "dev", mode: "rules" },
      { ts: "2026-11-02T23:00:00+09:00", set: "dev", mode: "rules+claude" },
      { ts: "2026-11-03T11:00:00+09:00", set: "holdout", mode: "rules+claude" },
    ].map((l) => JSON.stringify(l));
    expect(countRunsOn(lines.join("\n"), "2026-11-03")).toBe(1);
  });

  it("writes a RESULTS.md row with the Japanese date alone and counts next to rates", () => {
    // The table is public, and public records give the date alone, so the row carries the date only; the
    // full ts stays in results.jsonl.
    const row = resultsRow({
      ts: "2026-11-05T15:04:00+09:00",
      set: "dev",
      mode: "rules",
      n: 20,
      notes: "first run",
      metrics: {
        misses: 3,
        miss_rate: 0.3,
        false_alarms: 0,
        false_alarm_rate: 0,
        genuine_at_level1: 0,
        unneeded_family_pushes: 0,
        p50_latency_ms: 0.04,
        p90_latency_ms: 0.1,
        by_source: {},
        scam: 10,
        genuine: 10,
        false_alarms_unguided: 0,
      },
    });
    expect(row).toBe("| 2026年11月5日 | dev | rules | 20 | 30.0% (3/10) | 0.0% (0/10) | 0 | 0.04 | first run |");
  });
});

describe("judge", () => {
  const undecided: RuleResult = { level: null, reasons: [], confident: false };
  const notConfident: RuleResult = { level: 2, reasons: ["急がせる言い回しがある"], confident: false };
  const answer: ClaudeJudgment = {
    level: 3,
    reasons: ["本文に判定への指示がある"],
    message_to_protected: "家族に確かめて",
    injection_suspected: true,
  };

  it("stops clearly without an API key, so no numbers are made up", async () => {
    for (const key of [undefined, ""]) {
      const judge = loadJudge(key);
      await expect(judge({ source: "sms", text: "x" }, undecided)).rejects.toThrow(JudgeUnavailableError);
      await expect(judge({ source: "sms" }, undecided)).rejects.toThrow("ANTHROPIC_API_KEY");
    }
    await expect(unavailableJudge({ source: "sms" }, undecided)).rejects.toThrow(JudgeUnavailableError);
  });

  it("combines the rules and Claude with decide, the same as the judge queue", async () => {
    const asked: unknown[] = [];
    const judge = claudeJudge(async (input, rule) => {
      asked.push([input, rule]);
      return { ...answer, message_to_protected: "" };
    });
    // Rule 2 is the floor, then one step heavier for the injection. Claude's own answer comes along
    // for eval/out/dev-latest.json (#109).
    expect(await judge({ source: "sms", text: "x" }, notConfident)).toEqual({
      level: 1,
      checking: false,
      claude: { level: 3, reasons: ["本文に判定への指示がある"], injection_suspected: true },
    });
    expect(asked).toEqual([[{ source: "sms", text: "x" }, notConfident]]);
  });

  it("falls back to the rules, or level 2 when they did not decide, and says Claude gave nothing", async () => {
    const judge = claudeJudge(async () => null);
    expect(await judge({ source: "consult", text: "x" }, notConfident)).toEqual({ level: 2, checking: true });
    expect(await judge({ source: "consult", text: "x" }, undecided)).toEqual({ level: 2, checking: true });
  });

  it("keeps an SMS, a mail or a page neither decided out of the family's count, as the queue does (#137)", async () => {
    const judge = claudeJudge(async () => null);
    for (const source of ["sms", "gmail", "page"] as const) {
      expect(await judge({ source, text: "x" }, undecided)).toEqual({ level: 3, checking: true });
      expect(await judge({ source, text: "x" }, notConfident)).toEqual({ level: 2, checking: true });
    }
  });

  it("calls the Claude API with the key it was given and parses the answer", async () => {
    const keys: Array<string | null> = [];
    network.use(
      http.post("https://api.anthropic.com/v1/messages", ({ request }) => {
        keys.push(request.headers.get("x-api-key"));
        return HttpResponse.json({
          id: "msg_test",
          type: "message",
          role: "assistant",
          model: "claude-haiku-5-5",
          content: [{ type: "text", text: JSON.stringify(answer) }],
          stop_reason: "end_turn",
        });
      }),
    );
    const judge = loadJudge("eval-test-key");
    expect(await judge({ source: "sms", text: "x" }, undecided)).toEqual({
      level: 2,
      checking: false,
      claude: { level: 3, reasons: ["本文に判定への指示がある"], injection_suspected: true },
    });
    expect(keys).toEqual(["eval-test-key"]);
  });
});

// Consultations are scored on the path POST /consult takes (#74): the fake-police script from the
// rules alone, otherwise the rules and the consultation Claude (Sonnet), not the judge queue's.
describe("judgeCases", () => {
  const evalCase = (overrides: Partial<EvalCase>): EvalCase => ({
    id: "x-1",
    source: "consult",
    sender: null,
    domain: null,
    text: null,
    url: null,
    expected_level: 1,
    is_scam: true,
    note: "self-written",
    ...overrides,
  });
  // A caller who says he is the police and the account part: the script, so level 1 without Claude.
  // The rules alone put this text at 2, so only the consultation path makes it 1.
  const SCRIPT = "警察から電話があって、口座が犯罪に使われてるって言われたの";
  const NOTHING = "Wi-Fi がつながらないの";
  const refuse: Judge = async () => {
    throw new Error("the judge queue's Claude was asked");
  };
  const refuseConsult: ConsultJudge = async () => {
    throw new Error("the consultation Claude was asked");
  };
  const scamAnswer: ClaudeConsult = {
    kind: "scam",
    level: 2,
    reasons: ["知らない相手からの電話"],
    basis: "詐欺の手口と似ているところがあります。",
    action: "電話を切って家族に確かめて",
    handoff: false,
    injection_suspected: false,
    topic: "電話の相談",
  };

  it("puts a consultation that tells the script at level 1 in the rules row, without Claude", async () => {
    expect(judgeByRules({ source: "consult", text: SCRIPT }).level).toBe(2);
    const [scored] = await judgeCases([evalCase({ text: SCRIPT })], "rules", { judge: refuse, consult: refuseConsult });
    expect(scored).toMatchObject({ level: 1, rule_level: 2, consult_script: true });
    expect(scored).not.toHaveProperty("claude_answered");
  });

  it("keeps the rules' level for other consultations in the rules row, not the level 2 sent when Claude fails", async () => {
    const [scored] = await judgeCases([evalCase({ text: NOTHING, is_scam: false, expected_level: null })], "rules", {
      judge: refuse,
      consult: refuseConsult,
    });
    expect(scored).toMatchObject({ level: null, rule_level: null, consult_script: false });
  });

  it("scores SMS, mail, and pages by the rules alone as before, even when they tell the script", async () => {
    const others = (["sms", "gmail", "page"] as const).map((source) => evalCase({ id: source, source, text: SCRIPT }));
    const scored = await judgeCases(others, "rules", { judge: refuse, consult: refuseConsult });
    for (const [i, c] of others.entries()) {
      const rule = judgeByRules(toRuleInput(c));
      expect(rule.level).not.toBe(1);
      expect(scored[i]).toMatchObject({
        level: rule.level,
        rule_level: rule.level,
        confident: rule.confident,
        reasons: rule.reasons,
      });
      expect(scored[i]).not.toHaveProperty("consult_script");
    }
  });

  it("does not ask Claude for the script in rules+claude, as POST /consult does not", async () => {
    const [scored] = await judgeCases([evalCase({ text: SCRIPT })], "rules+claude", {
      judge: refuse,
      consult: refuseConsult,
    });
    expect(scored).toMatchObject({ level: 1, consult_script: true });
    expect(scored).not.toHaveProperty("claude_answered");
  });

  it("asks the consultation Claude, not the judge queue's, for other consultations in rules+claude", async () => {
    const asked: unknown[] = [];
    const consult: ConsultJudge = async (text, rule) => {
      asked.push([text, rule]);
      return scamAnswer;
    };
    const [scored] = await judgeCases([evalCase({ text: NOTHING })], "rules+claude", { judge: refuse, consult });
    expect(scored).toMatchObject({ level: 2, consult_script: false, claude_answered: true });
    expect(asked).toEqual([[NOTHING, judgeByRules({ source: "consult", text: NOTHING })]]);
  });

  it("combines the consultation answer as POST /consult does: level 3 help stays with her", async () => {
    const help: ClaudeConsult = {
      ...scamAnswer,
      kind: "help",
      level: 3,
      reasons: [],
      basis: "",
      action: "設定を開いて Wi-Fi を選んで",
    };
    const [scored] = await judgeCases(
      [evalCase({ text: NOTHING, is_scam: false, expected_level: null })],
      "rules+claude",
      {
        judge: refuse,
        consult: async () => help,
      },
    );
    expect(scored).toMatchObject({ level: 3, claude_answered: true });
  });

  it("counts level 2 when the consultation Claude gives nothing, since the family is told then", async () => {
    const [scored] = await judgeCases([evalCase({ text: NOTHING })], "rules+claude", {
      judge: refuse,
      consult: async () => null,
    });
    expect(scored).toMatchObject({ level: 2, claude_answered: false });
  });

  it("keeps the judge queue's Claude for SMS, mail, and pages in rules+claude", async () => {
    const seen: string[] = [];
    const judge: Judge = async (input) => {
      seen.push(input.source);
      return { level: 2, checking: false };
    };
    const others = (["sms", "gmail", "page"] as const).map((source) => evalCase({ id: source, source, text: SCRIPT }));
    const scored = await judgeCases(others, "rules+claude", { judge, consult: refuseConsult });
    expect(seen).toEqual(["sms", "gmail", "page"]);
    expect(scored.map((c) => c.level)).toEqual([2, 2, 2]);
  });

  it("asks Claude about an SMS only where the SMS route queues it: not for a verification code (#137)", async () => {
    const CODE = "認証コードは 482913 です。このコードを誰にも教えないでください。";
    const BROKEN_PHONE = "お母さん、携帯が壊れて番号が変わった。新しい番号に連絡して";
    const seen: Array<string | undefined> = [];
    const judge: Judge = async (input) => {
      seen.push(input.text);
      return { level: 2, checking: false };
    };
    const sms = (id: string, text: string) => evalCase({ id, source: "sms", text, is_scam: false, expected_level: null });
    const [code, broken] = await judgeCases([sms("code", CODE), sms("broken", BROKEN_PHONE)], "rules+claude", {
      judge,
      consult: refuseConsult,
    });
    expect(seen).toEqual([BROKEN_PHONE]);
    expect(code).toMatchObject({ level: null, rule_level: null });
    expect(code?.claude_answered).toBeUndefined();
    expect(broken).toMatchObject({ level: 2, rule_level: null, claude_answered: true });
  });

  it("asks Claude about a page only where the page route would send it (#137)", async () => {
    const seen: Array<string | undefined> = [];
    const judge: Judge = async (input) => {
      seen.push(input.url);
      return { level: 2, checking: false };
    };
    const page = (id: string, url: string, text: string) =>
      evalCase({ id, source: "page", url, text, is_scam: false, expected_level: null });
    const FAKE = "https://secure-account-check.com/login";
    const [recipe, fake] = await judgeCases(
      [page("recipe", "https://cookpad.com/recipe/1", "肉じゃがの作り方。"), page("fake", FAKE, "Amazon サインイン")],
      "rules+claude",
      { judge, consult: refuseConsult },
    );
    expect(seen).toEqual([FAKE]);
    expect(recipe).toMatchObject({ level: null });
    expect(recipe?.claude_answered).toBeUndefined();
    expect(fake).toMatchObject({ level: 2, claude_answered: true });
  });

  // #109: which false alarms the family gets by design, and what Claude itself answered.
  describe("what a run keeps to tell the false alarms apart (#109)", () => {
    const SEND_MONEY = "振込のやり方を教えて";
    const help: ClaudeConsult = {
      ...scamAnswer,
      kind: "help",
      level: 3,
      reasons: [],
      basis: "",
      action: "銀行の窓口で聞いてね",
    };
    const genuine = (text: string) => evalCase({ text, is_scam: false, expected_level: null });

    it("marks a consultation on a topic the AI does not guide, which reaches the family whatever Claude says", async () => {
      const [scored] = await judgeCases([genuine(SEND_MONEY)], "rules+claude", {
        judge: refuse,
        consult: async () => help,
      });
      expect(scored).toMatchObject({ level: 2, unguided_topic: true, claude_answered: true });
    });

    it("does not mark a consultation Claude put at level 2 on its own", async () => {
      const [scored] = await judgeCases([genuine(NOTHING)], "rules+claude", {
        judge: refuse,
        consult: async () => scamAnswer,
      });
      expect(scored).toMatchObject({ level: 2, unguided_topic: false });
    });

    it("marks nothing in the rules row, which does not hand any topic to the family", async () => {
      const [scored] = await judgeCases([genuine(SEND_MONEY)], "rules", { judge: refuse, consult: refuseConsult });
      expect(scored).not.toHaveProperty("unguided_topic");
      expect(scored).not.toHaveProperty("claude");
    });

    it("keeps the consultation Claude's own answer: kind, level, reasons, handoff, and the injection flag", async () => {
      const answer: ClaudeConsult = { ...help, reasons: ["通帳は本人しか見られない"], handoff: true };
      const [scored] = await judgeCases([genuine(NOTHING)], "rules+claude", {
        judge: refuse,
        consult: async () => answer,
      });
      expect(scored?.claude).toEqual({
        kind: "help",
        level: 3,
        reasons: ["通帳は本人しか見られない"],
        handoff: true,
        injection_suspected: false,
      });
      // Claude said 3 and the handoff took it to the family at 2: the record shows both.
      expect(scored?.level).toBe(2);
    });

    it("keeps nothing of Claude when it gave nothing", async () => {
      const [scored] = await judgeCases([genuine(NOTHING)], "rules+claude", {
        judge: refuse,
        consult: async () => null,
      });
      expect(scored).not.toHaveProperty("claude");
    });

    it("keeps the judge queue Claude's own answer for SMS, mail, and pages", async () => {
      const seen = { level: 2 as const, reasons: ["本物か確かめられない"], injection_suspected: false };
      const judge: Judge = async () => ({ level: 2, checking: false, claude: seen });
      const [scored] = await judgeCases([evalCase({ source: "sms", text: NOTHING, is_scam: false })], "rules+claude", {
        judge,
        consult: refuseConsult,
      });
      expect(scored?.claude).toEqual(seen);
      expect(scored).not.toHaveProperty("unguided_topic");
    });
  });

  it("stops clearly without an API key for consultations too", async () => {
    for (const key of [undefined, ""]) {
      await expect(loadConsultJudge(key)(NOTHING, judgeByRules({ source: "consult", text: NOTHING }))).rejects.toThrow(
        JudgeUnavailableError,
      );
    }
    await expect(
      judgeCases([evalCase({ text: NOTHING })], "rules+claude", { judge: refuse, consult: unavailableConsultJudge }),
    ).rejects.toThrow(JudgeUnavailableError);
  });

  it("calls the consultation model with the key it was given", async () => {
    const seen: Array<{ key: string | null; model: unknown }> = [];
    network.use(
      http.post("https://api.anthropic.com/v1/messages", async ({ request }) => {
        const body = (await request.json()) as { model: unknown };
        seen.push({ key: request.headers.get("x-api-key"), model: body.model });
        return HttpResponse.json({
          id: "msg_test",
          type: "message",
          role: "assistant",
          model: "claude-sonnet-5-5",
          content: [{ type: "text", text: JSON.stringify(scamAnswer) }],
          stop_reason: "end_turn",
        });
      }),
    );
    const answer = await loadConsultJudge("eval-test-key")(NOTHING, judgeByRules({ source: "consult", text: NOTHING }));
    expect(answer).toEqual(scamAnswer);
    expect(seen).toEqual([{ key: "eval-test-key", model: "claude-sonnet-5-5" }]);
  });
});
