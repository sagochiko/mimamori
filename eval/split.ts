// `make eval-split`: moves whole pattern files from eval/cases/pool into eval/cases/dev and
// eval/cases/holdout by the rule in eval/README.md (eval/lib/split-plan.ts). It checks every file
// before moving any, prints only counts (and dev file names), and adds the counts to
// eval/split-counts.json, which fixes the denominators. Case text is never printed.
//
//   cd server && npx tsx ../eval/split.ts [--dry-run]

import { access, readdir, readFile, rename, writeFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { parseCases } from "./lib/cases";
import { groupKey, planSplit, type PatternFile, type SplitPlan } from "./lib/split-plan";

export interface SplitDirs {
  pool: string;
  dev: string;
  holdout: string;
  countsFile: string;
  dryRun?: boolean;
}

type Counts = Record<string, { dev: number; holdout: number }>;

async function exists(file: string): Promise<boolean> {
  try {
    await access(file);
    return true;
  } catch {
    return false;
  }
}

async function readPatterns(pool: string): Promise<PatternFile[]> {
  const names = (await readdir(pool)).filter((name) => name.endsWith(".jsonl")).sort();
  const seen = new Map<string, string>();
  const files: PatternFile[] = [];
  for (const name of names) {
    const cases = parseCases(await readFile(path.join(pool, name), "utf8"), name);
    if (cases.length === 0) throw new Error(`${name}: no cases`);
    const keys = new Set(cases.map((c) => groupKey({ source: c.source, isScam: c.is_scam })));
    if (keys.size !== 1) {
      throw new Error(`${name}: a pattern file must hold one path and one of scam or genuine (found ${[...keys].join(", ")})`);
    }
    for (const c of cases) {
      const other = seen.get(c.id);
      if (other) throw new Error(`duplicate id ${c.id} in ${other} and ${name}`);
      seen.set(c.id, name);
    }
    files.push({ name, source: cases[0]!.source, isScam: cases[0]!.is_scam, count: cases.length });
  }
  return files;
}

function report(plan: SplitPlan, dryRun: boolean): string[] {
  const lines = [dryRun ? "dry run: nothing moved" : "moved from the pool:"];
  const width = Math.max(...plan.groups.map((g) => g.key.length));
  for (const g of plan.groups) {
    const injection = g.dev.injection + g.holdout.injection > 0 ? `  injection dev ${g.dev.injection} / holdout ${g.holdout.injection}` : "";
    lines.push(
      `  ${g.key.padEnd(width)}  dev ${g.dev.cases} (${g.dev.files} files)  holdout ${g.holdout.cases} (${g.holdout.files} files)${injection}`,
    );
  }
  const total = (set: "dev" | "holdout") => plan.groups.reduce((sum, g) => sum + g[set].cases, 0);
  lines.push(`  total  dev ${total("dev")}  holdout ${total("holdout")}`);
  lines.push(`dev files: ${plan.assignments.filter((a) => a.set === "dev").map((a) => a.name).join(", ") || "-"}`);
  return lines;
}

export async function splitPool(dirs: SplitDirs): Promise<{ plan: SplitPlan | null; lines: string[] }> {
  const files = await readPatterns(dirs.pool);
  if (files.length === 0) return { plan: null, lines: ["pool is empty: nothing to split"] };

  for (const file of files) {
    for (const dir of [dirs.dev, dirs.holdout]) {
      if (await exists(path.join(dir, file.name))) {
        throw new Error(`${file.name} already exists in ${path.basename(dir)}; rename the pattern in the pool`);
      }
    }
  }

  const plan = planSplit(files);
  if (dirs.dryRun) return { plan, lines: report(plan, true) };

  for (const { name, set } of plan.assignments) {
    await rename(path.join(dirs.pool, name), path.join(set === "dev" ? dirs.dev : dirs.holdout, name));
  }

  const counts: Counts = (await exists(dirs.countsFile)) ? JSON.parse(await readFile(dirs.countsFile, "utf8")) : {};
  for (const g of plan.groups) {
    const before = counts[g.key] ?? { dev: 0, holdout: 0 };
    counts[g.key] = { dev: before.dev + g.dev.cases, holdout: before.holdout + g.holdout.cases };
  }
  const sorted = Object.fromEntries(Object.entries(counts).sort(([a], [b]) => (a < b ? -1 : 1)));
  await writeFile(dirs.countsFile, `${JSON.stringify(sorted, null, 2)}\n`);
  return { plan, lines: [...report(plan, false), `counts added to ${path.basename(dirs.countsFile)}`] };
}

async function main() {
  const here = import.meta.dirname;
  const cases = path.join(here, "cases");
  const { lines } = await splitPool({
    pool: path.join(cases, "pool"),
    dev: path.join(cases, "dev"),
    holdout: path.join(cases, "holdout"),
    countsFile: path.join(here, "split-counts.json"),
    dryRun: process.argv.includes("--dry-run"),
  });
  console.log(lines.join("\n"));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error: unknown) => {
    console.error(`eval-split: ${error instanceof Error ? error.message : String(error)}`);
    process.exit(1);
  });
}
