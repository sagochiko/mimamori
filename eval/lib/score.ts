// Scoring one run. The definitions are fixed in eval/README.md before any measurement:
// - a miss is a scam that does not reach the family: level null (the rules could not decide) or 3
// - a false alarm is a genuine case at level 1 or 2, which sends the family a push it did not need
// - genuine_at_level1 counts genuine cases at level 1 (junk folder, DNS block); the target is 0
// - false_alarms_unguided counts the false alarms that are consultations on a topic the AI does not
//   guide (sending money, codes, profiles, deleting data), which go to the family whatever Claude says
//   (decidePlan in server/src/consult-judge.ts). They stay in false_alarms too (#109).
// No Node APIs here, so the server's Vitest (in workerd) can import this file.

import { consultByRules, judgeConsult } from "../../server/src/consult-judge";
import { judgeByRules, type RuleInput } from "../../server/src/rules/index";
import type { CaseSource, EvalCase } from "./cases";
import type { ClaudeSeen, ConsultJudge, Judge } from "./judge";

export type Mode = "rules" | "rules+claude";
type Level = 1 | 2 | 3 | null;

export interface ScoredCase {
  id: string;
  source: CaseSource;
  is_scam: boolean;
  expected_level: Level;
  level: Level;
  latency_ms: number;
  rule_level?: Level;
  confident?: boolean;
  reasons?: string[];
  /** rules+claude only: false when Claude gave nothing usable and the rules stood alone. Absent when Claude was not asked. */
  claude_answered?: boolean;
  /** Consultations only: the fake-police script decided it from the rules alone. */
  consult_script?: boolean;
  /**
   * Consultations in rules+claude only: her words are on a topic the AI does not guide, so the family
   * takes it whatever Claude answers (#109). Absent for the script, where Claude is not asked.
   */
  unguided_topic?: boolean;
  /** rules+claude only: what Claude itself answered (#109); absent when Claude gave nothing or was not asked. */
  claude?: ClaudeSeen & { kind?: "scam" | "help"; handoff?: boolean };
}

/** The two Claude calls of rules+claude: the judge queue's for messages and pages, and the consultation one. */
export interface EvalClaude {
  judge: Judge;
  consult: ConsultJudge;
}

export interface SourceMetrics {
  n: number;
  scam: number;
  genuine: number;
  misses: number;
  miss_rate: number | null;
  false_alarms: number;
  false_alarm_rate: number | null;
  genuine_at_level1: number;
  /** Of false_alarms, the consultations on a topic the AI does not guide (#109). */
  false_alarms_unguided: number;
}

// The first seven fields are the contract in docs/plan.md (task 4). The rest are what eval/README.md
// also asks for: the slow tenth of the latency, genuine cases at level 1, and the denominators.
export interface RunMetrics {
  misses: number;
  miss_rate: number | null;
  false_alarms: number;
  false_alarm_rate: number | null;
  unneeded_family_pushes: number;
  p50_latency_ms: number | null;
  by_source: Partial<Record<CaseSource, SourceMetrics>>;
  p90_latency_ms: number | null;
  genuine_at_level1: number;
  scam: number;
  genuine: number;
  /** Of false_alarms, the consultations on a topic the AI does not guide (#109). */
  false_alarms_unguided: number;
}

/** Level 1 and 2 reach the family (task 6 sends no push for level 3). */
export function reachesFamily(level: Level): boolean {
  return level === 1 || level === 2;
}

function rate(count: number, total: number): number | null {
  return total === 0 ? null : count / total;
}

/** Nearest-rank percentile. */
export function percentile(values: readonly number[], p: number): number | null {
  if (values.length === 0) return null;
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.max(0, Math.ceil((p / 100) * sorted.length) - 1)]!;
}

function round(ms: number | null): number | null {
  return ms === null ? null : Math.round(ms * 100) / 100;
}

function tally(cases: readonly ScoredCase[]): SourceMetrics {
  const scam = cases.filter((c) => c.is_scam);
  const genuine = cases.filter((c) => !c.is_scam);
  const misses = scam.filter((c) => !reachesFamily(c.level)).length;
  const falseAlarms = genuine.filter((c) => reachesFamily(c.level));
  return {
    n: cases.length,
    scam: scam.length,
    genuine: genuine.length,
    misses,
    miss_rate: rate(misses, scam.length),
    false_alarms: falseAlarms.length,
    false_alarm_rate: rate(falseAlarms.length, genuine.length),
    genuine_at_level1: genuine.filter((c) => c.level === 1).length,
    false_alarms_unguided: falseAlarms.filter((c) => c.unguided_topic === true).length,
  };
}

export function scoreRun(cases: readonly ScoredCase[]): RunMetrics {
  const all = tally(cases);
  const bySource: RunMetrics["by_source"] = {};
  for (const source of [...new Set(cases.map((c) => c.source))].sort()) {
    bySource[source] = tally(cases.filter((c) => c.source === source));
  }
  const latencies = cases.map((c) => c.latency_ms);
  return {
    misses: all.misses,
    miss_rate: all.miss_rate,
    false_alarms: all.false_alarms,
    false_alarm_rate: all.false_alarm_rate,
    // Every false alarm is a push to the family. Grouping repeats from one sender (task 6) is not
    // modelled here, so this equals false_alarms until that exists.
    unneeded_family_pushes: all.false_alarms,
    p50_latency_ms: round(percentile(latencies, 50)),
    by_source: bySource,
    p90_latency_ms: round(percentile(latencies, 90)),
    genuine_at_level1: all.genuine_at_level1,
    scam: all.scam,
    genuine: all.genuine,
    false_alarms_unguided: all.false_alarms_unguided,
  };
}

export function toRuleInput(c: EvalCase): RuleInput {
  const input: RuleInput = { source: c.source };
  if (c.sender !== null) input.sender = c.sender;
  if (c.domain !== null) input.domain = c.domain;
  if (c.text !== null) input.text = c.text;
  if (c.url !== null) input.url = c.url;
  return input;
}

/**
 * Judges every case. The latency is the judging time only, not delivery to the family.
 * A consultation is judged on the path POST /consult takes (#74), with no earlier turns: the
 * fake-police script is level 1 from the rules alone and Claude is not asked. Otherwise rules+claude
 * asks the consultation Claude and judgeConsult decides, as for her; the rules row takes the rules'
 * level on her words. That rules row is not POST /consult without Claude, which tells the family at
 * level 2 when the rules do not decide (decidePlan in server/src/consult-judge.ts).
 */
export async function judgeCases(
  cases: readonly EvalCase[],
  mode: Mode,
  claude: EvalClaude,
  now: () => number = () => performance.now(),
): Promise<ScoredCase[]> {
  const scored: ScoredCase[] = [];
  for (const c of cases) {
    const base = { id: c.id, source: c.source, is_scam: c.is_scam, expected_level: c.expected_level };
    const start = now();
    if (c.source === "consult") {
      const text = c.text ?? "";
      if (mode === "rules") {
        const { rule, script } = consultByRules(text);
        const latency = now() - start;
        scored.push({
          ...base,
          level: script ? 1 : rule.level,
          latency_ms: latency,
          rule_level: rule.level,
          confident: rule.confident,
          reasons: rule.reasons,
          consult_script: script,
        });
        continue;
      }
      let answered: boolean | undefined;
      let seen: ScoredCase["claude"];
      const judged = await judgeConsult(text, [], async (rule) => {
        const answer = await claude.consult(text, rule);
        answered = answer !== null;
        if (answer !== null) {
          const { kind, level, reasons, handoff, injection_suspected } = answer;
          seen = { kind, level, reasons, handoff, injection_suspected };
        }
        return answer;
      });
      const latency = now() - start;
      scored.push({
        ...base,
        level: judged.level,
        latency_ms: latency,
        rule_level: judged.rule.level,
        confident: judged.rule.confident,
        reasons: judged.reasons,
        consult_script: judged.script,
        ...(answered === undefined ? {} : { claude_answered: answered }),
        ...(judged.script ? {} : { unguided_topic: judged.unguided }),
        ...(seen === undefined ? {} : { claude: seen }),
      });
      continue;
    }
    const input = toRuleInput(c);
    const rule = judgeByRules(input);
    const combined = mode === "rules" ? null : await claude.judge(input, rule);
    const level = combined === null ? rule.level : combined.level;
    const latency = now() - start;
    scored.push({
      ...base,
      level,
      latency_ms: latency,
      rule_level: rule.level,
      confident: rule.confident,
      reasons: rule.reasons,
      ...(combined === null ? {} : { claude_answered: combined.checking !== true }),
      ...(combined?.claude === undefined ? {} : { claude: combined.claude }),
    });
  }
  return scored;
}

/** rules+claude runs on the dev set on one JST date ("2026-11-03"); the daily budget counts these. */
export function countRunsOn(resultsJsonl: string, date: string): number {
  let count = 0;
  for (const raw of resultsJsonl.split("\n")) {
    if (raw.trim() === "") continue;
    try {
      const r = JSON.parse(raw) as { ts?: string; set?: string; mode?: string };
      if (r.set === "dev" && r.mode === "rules+claude" && r.ts?.startsWith(date)) count++;
    } catch {
      // A broken line is not a run.
    }
  }
  return count;
}

function percent(count: number, total: number): string {
  return total === 0 ? "-" : `${((count / total) * 100).toFixed(1)}% (${count}/${total})`;
}

/**
 * The date alone, "2026年11月5日". RESULTS.md is public, and public records give the date alone; the
 * full ts stays in results.jsonl.
 */
function japaneseDate(ts: string): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(ts);
  if (!m) return ts;
  return `${m[1]}年${Number(m[2])}月${Number(m[3])}日`;
}

export interface RunRecord {
  ts: string;
  set: string;
  mode: Mode;
  n: number;
  notes: string;
  metrics: RunMetrics;
}

/** One row for the table in eval/RESULTS.md. */
export function resultsRow(r: RunRecord): string {
  const m = r.metrics;
  const notes = r.notes.replace(/\|/g, "\\|").replace(/\s+/g, " ").trim() || "-";
  const p50 = m.p50_latency_ms === null ? "-" : String(m.p50_latency_ms);
  return `| ${japaneseDate(r.ts)} | ${r.set} | ${r.mode} | ${r.n} | ${percent(m.misses, m.scam)} | ${percent(
    m.false_alarms,
    m.genuine,
  )} | ${m.unneeded_family_pushes} | ${p50} | ${notes} |`;
}
