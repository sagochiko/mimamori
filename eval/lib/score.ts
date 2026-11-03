// Scoring one run. The definitions are fixed in eval/README.md before any measurement:
// - a miss is a scam that does not reach the family: level null (the rules could not decide) or 3
// - a false alarm is a genuine case at level 1 or 2, which sends the family a push it did not need
// - genuine_at_level1 counts genuine cases at level 1 (junk folder, DNS block); the target is 0
// No Node APIs here, so the server's Vitest (in workerd) can import this file.

import { judgeByRules, type RuleInput } from "../../server/src/rules/index";
import type { CaseSource, EvalCase } from "./cases";
import type { Judge } from "./judge";

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
  const falseAlarms = genuine.filter((c) => reachesFamily(c.level)).length;
  return {
    n: cases.length,
    scam: scam.length,
    genuine: genuine.length,
    misses,
    miss_rate: rate(misses, scam.length),
    false_alarms: falseAlarms,
    false_alarm_rate: rate(falseAlarms, genuine.length),
    genuine_at_level1: genuine.filter((c) => c.level === 1).length,
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

/** Judges every case. The latency is the judging time only, not delivery to the family. */
export async function judgeCases(
  cases: readonly EvalCase[],
  mode: Mode,
  judge: Judge,
  now: () => number = () => performance.now(),
): Promise<ScoredCase[]> {
  const scored: ScoredCase[] = [];
  for (const c of cases) {
    const input = toRuleInput(c);
    const start = now();
    const rule = judgeByRules(input);
    const level = mode === "rules" ? rule.level : (await judge(input, rule)).level;
    const latency = now() - start;
    scored.push({
      id: c.id,
      source: c.source,
      is_scam: c.is_scam,
      expected_level: c.expected_level,
      level,
      latency_ms: latency,
      rule_level: rule.level,
      confident: rule.confident,
      reasons: rule.reasons,
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

function japaneseDate(ts: string): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/.exec(ts);
  if (!m) return ts;
  return `${m[1]}年${Number(m[2])}月${Number(m[3])}日 ${m[4]}:${m[5]}`;
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
