// Which pattern files go to dev and which to holdout. The rule is fixed in eval/README.md:
// - a pattern file moves whole, so wording variants of one scam never sit on both sides
// - each group (path x scam or genuine) is split into two halves as equal as possible by case count
// - on a tie, the holdout gets the larger half, then injection cases are spread across both sides,
//   then the lowest combination in a fixed hash order of the file names wins
// It looks only at names and counts, so it is the same on every machine and in every file order.
// No Node APIs here, so the server's Vitest (in workerd) can import this file.

import type { CaseSource } from "./cases";

export type SetName = "dev" | "holdout";

export interface PatternFile {
  name: string;
  source: CaseSource;
  isScam: boolean;
  count: number;
}

export interface SideCount {
  files: number;
  cases: number;
  injection: number;
}

export interface GroupPlan {
  key: string;
  dev: SideCount;
  holdout: SideCount;
}

export interface SplitPlan {
  assignments: Array<{ name: string; set: SetName }>;
  groups: GroupPlan[];
}

// Above this many files in one group, trying every combination (2^n) is too slow; fall back to greedy.
const EXHAUSTIVE_LIMIT = 20;

export function isInjectionPattern(name: string): boolean {
  return /injection/i.test(name);
}

export function groupKey(file: Pick<PatternFile, "source" | "isScam">): string {
  return `${file.source}/${file.isScam ? "scam" : "genuine"}`;
}

// FNV-1a, 32 bits. Only for a stable order that does not follow the alphabet of the names.
function hashName(name: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < name.length; i++) {
    h ^= name.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h;
}

function byHash(a: PatternFile, b: PatternFile): number {
  return hashName(a.name) - hashName(b.name) || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0);
}

function injectionCount(file: PatternFile): number {
  return isInjectionPattern(file.name) ? file.count : 0;
}

/** For files in hash order, which go to the holdout. */
function chooseHoldout(files: PatternFile[]): boolean[] {
  const n = files.length;
  const total = files.reduce((sum, f) => sum + f.count, 0);
  const totalInjection = files.reduce((sum, f) => sum + injectionCount(f), 0);

  if (n > EXHAUSTIVE_LIMIT) {
    // Largest first, each to the side with fewer cases; ties go to the holdout.
    const order = files.map((f, i) => ({ f, i })).sort((a, b) => b.f.count - a.f.count || a.i - b.i);
    const holdout = new Array<boolean>(n).fill(false);
    let h = 0;
    let d = 0;
    for (const { f, i } of order) {
      if (h <= d) {
        holdout[i] = true;
        h += f.count;
      } else d += f.count;
    }
    return holdout;
  }

  let best: number[] | null = null;
  let bestMask = 0;
  for (let mask = 0; mask < 1 << n; mask++) {
    let h = 0;
    let hInjection = 0;
    for (let i = 0; i < n; i++) {
      if (mask & (1 << i)) {
        h += files[i]!.count;
        hInjection += injectionCount(files[i]!);
      }
    }
    const d = total - h;
    const cost = [Math.abs(h - d), h < d ? 1 : 0, Math.abs(2 * hInjection - totalInjection)];
    if (!best || lessThan(cost, best)) {
      best = cost;
      bestMask = mask;
    }
  }
  return files.map((_, i) => (bestMask & (1 << i)) !== 0);
}

function lessThan(a: number[], b: number[]): boolean {
  for (let k = 0; k < a.length; k++) {
    if (a[k]! !== b[k]!) return a[k]! < b[k]!;
  }
  return false;
}

export function planSplit(files: readonly PatternFile[]): SplitPlan {
  const groups = new Map<string, PatternFile[]>();
  for (const file of files) {
    const key = groupKey(file);
    groups.set(key, [...(groups.get(key) ?? []), file]);
  }

  const assignments: SplitPlan["assignments"] = [];
  const plans: GroupPlan[] = [];
  for (const key of [...groups.keys()].sort()) {
    const members = [...groups.get(key)!].sort(byHash);
    const holdout = chooseHoldout(members);
    const side = (): SideCount => ({ files: 0, cases: 0, injection: 0 });
    const plan: GroupPlan = { key, dev: side(), holdout: side() };
    members.forEach((file, i) => {
      const set: SetName = holdout[i] ? "holdout" : "dev";
      assignments.push({ name: file.name, set });
      plan[set].files += 1;
      plan[set].cases += file.count;
      plan[set].injection += injectionCount(file);
    });
    plans.push(plan);
  }
  assignments.sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
  return { assignments, groups: plans };
}
