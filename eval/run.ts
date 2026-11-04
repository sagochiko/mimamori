// `make eval`: measures one set in one mode and records it.
//
//   cd server && npx tsx ../eval/run.ts --set dev|holdout --mode rules|rules+claude [--notes "what changed"]
//   (or EVAL_NOTES="what changed" make eval)
//
// Output per run (task 4 of docs/plan.md): { misses, miss_rate, false_alarms, false_alarm_rate,
// unneeded_family_pushes, p50_latency_ms, by_source }, plus p90_latency_ms, genuine_at_level1 and the
// denominators (eval/README.md). Appends that with ts, set, mode, git_sha, n, notes to
// eval/results.jsonl and a row to eval/RESULTS.md. Prints totals only, never case text.
// Per-case results go to eval/out/dev-latest.json for the dev set only.

import { execFileSync } from "node:child_process";
import { access, appendFile, mkdir, readdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { parseCases, type EvalCase } from "./lib/cases";
import { type ConsultJudge, loadConsultJudge, loadJudge, type Judge, JudgeUnavailableError } from "./lib/judge";
import { countRunsOn, judgeCases, type Mode, resultsRow, type RunMetrics, scoreRun } from "./lib/score";
import { groupKey } from "./lib/split-plan";

export interface RunOptions {
  evalDir: string;
  set: "dev" | "holdout";
  mode: Mode;
  notes: string;
  /** ISO time with the +09:00 offset. Defaults to now in JST. */
  now?: string;
  judge?: Judge;
  /** The consultation Claude for rules+claude (eval/lib/score.ts). */
  consult?: ConsultJudge;
  /** For rules+claude when no judge is given. Defaults to ANTHROPIC_API_KEY in the environment. */
  apiKey?: string;
}

async function exists(file: string): Promise<boolean> {
  try {
    await access(file);
    return true;
  } catch {
    return false;
  }
}

function nowInJst(): string {
  return `${new Date(Date.now() + 9 * 3600_000).toISOString().slice(0, 19)}+09:00`;
}

function gitSha(cwd: string): string {
  try {
    return execFileSync("git", ["rev-parse", "--short", "HEAD"], { cwd, stdio: ["ignore", "pipe", "ignore"] })
      .toString()
      .trim();
  } catch {
    return "unknown";
  }
}

async function dailyBudget(repo: string): Promise<number> {
  const conditions = await readFile(path.join(repo, "CONDITIONS.md"), "utf8").catch(() => "");
  const m = /^eval_dev_runs_per_day:\s*(\d+)/m.exec(conditions);
  return m ? Number(m[1]) : 10;
}

async function loadSet(dir: string): Promise<EvalCase[]> {
  if (!(await exists(dir))) return [];
  const names = (await readdir(dir)).filter((name) => name.endsWith(".jsonl")).sort();
  const cases: EvalCase[] = [];
  for (const name of names) cases.push(...parseCases(await readFile(path.join(dir, name), "utf8"), name));
  return cases;
}

/** The denominators were fixed when the pool was split; say so if the set no longer matches. */
async function countWarnings(evalDir: string, set: RunOptions["set"], cases: EvalCase[]): Promise<string[]> {
  const file = path.join(evalDir, "split-counts.json");
  if (!(await exists(file))) return [];
  const fixed = JSON.parse(await readFile(file, "utf8")) as Record<string, { dev: number; holdout: number }>;
  const actual = new Map<string, number>();
  for (const c of cases) {
    const key = groupKey({ source: c.source, isScam: c.is_scam });
    actual.set(key, (actual.get(key) ?? 0) + 1);
  }
  const warnings: string[] = [];
  for (const key of [...new Set([...Object.keys(fixed), ...actual.keys()])].sort()) {
    const want = fixed[key]?.[set] ?? 0;
    const have = actual.get(key) ?? 0;
    if (want !== have) warnings.push(`warning: ${key} has ${have} cases in ${set}, split-counts.json says ${want}`);
  }
  return warnings;
}

function pct(count: number, total: number): string {
  return total === 0 ? "-" : `${count}/${total} (${((count / total) * 100).toFixed(1)}%)`;
}

function summary(set: string, mode: Mode, n: number, m: RunMetrics): string[] {
  const lines = [
    `${set} ${mode}: n=${n}  misses ${pct(m.misses, m.scam)}  false alarms ${pct(m.false_alarms, m.genuine)}  genuine at level 1: ${m.genuine_at_level1}  p50 ${m.p50_latency_ms}ms  p90 ${m.p90_latency_ms}ms`,
  ];
  for (const [source, s] of Object.entries(m.by_source)) {
    lines.push(`  ${source.padEnd(8)} misses ${pct(s.misses, s.scam)}  false alarms ${pct(s.false_alarms, s.genuine)}  level 1 genuine ${s.genuine_at_level1}`);
  }
  return lines;
}

export async function runEval(options: RunOptions): Promise<{ exitCode: number; lines: string[] }> {
  const { evalDir, set, mode } = options;
  const repo = path.dirname(evalDir);
  const ts = options.now ?? nowInJst();
  const lines: string[] = [];
  const stop = (message: string) => ({ exitCode: 1, lines: [...lines, message] });

  // The hook guard-holdout also blocks this; checking here keeps `make` runs honest too.
  if (set === "holdout" && !(await exists(path.join(repo, ".claude", "state", "holdout.unlock")))) {
    return stop("holdout is locked: it is measured once, after the author creates .claude/state/holdout.unlock");
  }

  const cases = await loadSet(path.join(evalDir, "cases", set));
  if (cases.length === 0) return stop(`no cases in eval/cases/${set}: run make eval-split first`);
  lines.push(...(await countWarnings(evalDir, set, cases)));

  const resultsFile = path.join(evalDir, "results.jsonl");
  const previous = await readFile(resultsFile, "utf8").catch(() => "");
  if (mode === "rules+claude" && set === "dev") {
    const budget = await dailyBudget(repo);
    const used = countRunsOn(previous, ts.slice(0, 10));
    if (used >= budget) return stop(`daily budget used: ${used} of ${budget} rules+claude dev runs today (CONDITIONS.md)`);
  }

  let scored;
  const apiKey = "apiKey" in options ? options.apiKey : process.env.ANTHROPIC_API_KEY;
  try {
    scored = await judgeCases(cases, mode, {
      judge: options.judge ?? loadJudge(apiKey),
      consult: options.consult ?? loadConsultJudge(apiKey),
    });
  } catch (error) {
    if (error instanceof JudgeUnavailableError) return stop(error.message);
    throw error;
  }
  const metrics = scoreRun(scored);

  // A rules+claude run where Claude often gave nothing is mostly the rules; say how often.
  const unanswered = mode === "rules+claude" ? scored.filter((c) => c.claude_answered === false).length : null;
  const record = {
    ...metrics,
    ts,
    set,
    mode,
    git_sha: gitSha(evalDir),
    n: cases.length,
    notes: options.notes,
    ...(unanswered === null ? {} : { claude_unanswered: unanswered }),
  };
  await appendFile(resultsFile, `${previous && !previous.endsWith("\n") ? "\n" : ""}${JSON.stringify(record)}\n`);
  const resultsMd = path.join(evalDir, "RESULTS.md");
  const table = await readFile(resultsMd, "utf8").catch(() => "");
  const row = resultsRow({ ts, set, mode, n: cases.length, notes: options.notes, metrics });
  await appendFile(resultsMd, `${table && !table.endsWith("\n") ? "\n" : ""}${row}\n`);

  // Per-case results help tuning, so only the dev set gets them.
  if (set === "dev") {
    await mkdir(path.join(evalDir, "out"), { recursive: true });
    await writeFile(path.join(evalDir, "out", "dev-latest.json"), `${JSON.stringify({ ...record, cases: scored }, null, 2)}\n`);
  }

  lines.push(...summary(set, mode, cases.length, metrics));
  if (unanswered !== null) lines.push(`  claude gave nothing for ${unanswered} of ${cases.length}`);
  return { exitCode: 0, lines };
}

function argValue(args: string[], name: string): string | undefined {
  const i = args.indexOf(name);
  if (i >= 0) return args[i + 1];
  return args.find((a) => a.startsWith(`${name}=`))?.slice(name.length + 1);
}

async function main() {
  const args = process.argv.slice(2);
  const set = argValue(args, "--set");
  const mode = argValue(args, "--mode");
  if ((set !== "dev" && set !== "holdout") || (mode !== "rules" && mode !== "rules+claude")) {
    console.error("usage: eval/run.ts --set dev|holdout --mode rules|rules+claude [--notes text]");
    process.exit(2);
  }
  const { exitCode, lines } = await runEval({ evalDir: import.meta.dirname, set, mode, notes: argValue(args, "--notes") ?? process.env.EVAL_NOTES ?? "" });
  (exitCode === 0 ? console.log : console.error)(lines.join("\n"));
  process.exit(exitCode);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error: unknown) => {
    console.error(`eval: ${error instanceof Error ? error.message : String(error)}`);
    process.exit(1);
  });
}
