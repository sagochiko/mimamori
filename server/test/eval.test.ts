// The pure parts of eval/: reading cases, splitting patterns, and scoring a run. The parts that touch
// files are tested on temporary folders in eval/test/ (run with `npx tsx --test`).

import { http, HttpResponse } from "msw";
import { describe, expect, it } from "vitest";
import { parseCases, type EvalCase } from "../../eval/lib/cases";
import { claudeJudge, JudgeUnavailableError, loadJudge, unavailableJudge } from "../../eval/lib/judge";
import { countRunsOn, percentile, resultsRow, scoreRun } from "../../eval/lib/score";
import { planSplit, type PatternFile } from "../../eval/lib/split-plan";
import type { ClaudeJudgment } from "../src/claude";
import type { RuleResult } from "../src/rules";
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

  it("writes a RESULTS.md row with Japanese dates and counts next to rates", () => {
    const row = resultsRow({
      ts: "2026-11-03T23:05:00+09:00",
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
      },
    });
    expect(row).toBe("| 2026年11月3日 23:05 | dev | rules | 20 | 30.0% (3/10) | 0.0% (0/10) | 0 | 0.04 | first run |");
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
    // Rule 2 is the floor, then one step heavier for the injection.
    expect(await judge({ source: "sms", text: "x" }, notConfident)).toEqual({ level: 1, checking: false });
    expect(asked).toEqual([[{ source: "sms", text: "x" }, notConfident]]);
  });

  it("falls back to the rules, or level 2 when they did not decide, and says Claude gave nothing", async () => {
    const judge = claudeJudge(async () => null);
    expect(await judge({ source: "consult", text: "x" }, notConfident)).toEqual({ level: 2, checking: true });
    expect(await judge({ source: "consult", text: "x" }, undecided)).toEqual({ level: 2, checking: true });
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
    expect(await judge({ source: "sms", text: "x" }, undecided)).toEqual({ level: 2, checking: false });
    expect(keys).toEqual(["eval-test-key"]);
  });
});
