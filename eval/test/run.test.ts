// eval/run.ts on fixture cases in a temporary folder laid out like the repository.
// Run: cd server && npx tsx --test ../eval/test/*.test.ts

import assert from "node:assert/strict";
import { mkdir, mkdtemp, readdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, it } from "node:test";
import type { Judge } from "../lib/judge";
import { runEval } from "../run";

let repo: string;
let evalDir: string;
const TODAY = "2026-11-03T21:00:00+09:00";
const CONTRACT = [
  "misses",
  "miss_rate",
  "false_alarms",
  "false_alarm_rate",
  "unneeded_family_pushes",
  "p50_latency_ms",
  "by_source",
];

const cases = [
  // A look-alike domain with a deadline: the rules put it at level 1.
  {
    id: "dev-scam-1",
    source: "sms",
    sender: "+639000000000",
    domain: null,
    text: "FIXTURE-TEXT 【Amazon】本日中に更新しないとアカウントが停止されます https://amazon-pay-update.top/",
    url: null,
    expected_level: 1,
    is_scam: true,
    note: "self-written",
  },
  // Nothing the rules can see: a miss for the rules alone.
  {
    id: "dev-scam-2",
    source: "consult",
    sender: null,
    domain: null,
    text: "FIXTURE-TEXT 知らない人から電話があった",
    url: null,
    expected_level: 2,
    is_scam: true,
    note: "self-written",
  },
  {
    id: "dev-genuine-1",
    source: "gmail",
    sender: "ship@amazon.co.jp",
    domain: "amazon.co.jp",
    text: "FIXTURE-TEXT ご注文の商品を発送しました",
    url: null,
    expected_level: null,
    is_scam: false,
    note: "self-written",
  },
];

async function writeCases(set: string) {
  const dir = path.join(evalDir, "cases", set);
  await mkdir(dir, { recursive: true });
  await writeFile(path.join(dir, "fixture.jsonl"), `${cases.map((c) => JSON.stringify(c)).join("\n")}\n`);
}

const read = (file: string) => readFile(path.join(evalDir, file), "utf8");
const header = "| 日時 | セット | 方式 | 件数 | 見逃し率 | 誤判定率 | 要らない通知 | 中央値(ms) | 変えたこと |\n|---|---|---|---:|---:|---:|---:|---:|---|\n";

beforeEach(async () => {
  repo = await mkdtemp(path.join(tmpdir(), "mm-run-"));
  evalDir = path.join(repo, "eval");
  await mkdir(evalDir, { recursive: true });
  await writeFile(path.join(repo, "CONDITIONS.md"), "---\neval_dev_runs_per_day: 2\n---\n");
  await writeFile(path.join(evalDir, "RESULTS.md"), `# 精度の記録\n\n${header}`);
  await writeCases("dev");
});

afterEach(async () => {
  await rm(repo, { recursive: true, force: true });
});

describe("runEval --mode rules", () => {
  it("appends the contract output to results.jsonl and a row to RESULTS.md", async () => {
    const { exitCode, lines } = await runEval({ evalDir, set: "dev", mode: "rules", notes: "fixture", now: TODAY });
    assert.equal(exitCode, 0);

    const records = (await read("results.jsonl")).trim().split("\n").map((l) => JSON.parse(l));
    assert.equal(records.length, 1);
    const r = records[0];
    for (const key of [...CONTRACT, "ts", "set", "mode", "git_sha", "n", "notes"]) assert.ok(key in r, `missing ${key}`);
    assert.equal(r.ts, TODAY);
    assert.equal(r.set, "dev");
    assert.equal(r.mode, "rules");
    assert.equal(r.n, 3);
    assert.equal(r.misses, 1);
    assert.equal(r.miss_rate, 0.5);
    assert.equal(r.false_alarms, 0);
    assert.equal(r.genuine_at_level1, 0);
    assert.equal(r.by_source.consult.misses, 1);

    const results = await read("RESULTS.md");
    assert.ok(results.endsWith("| 2026年11月3日 21:00 | dev | rules | 3 | 50.0% (1/2) | 0.0% (0/1) | 0 | " + r.p50_latency_ms + " | fixture |\n"));

    const out = JSON.parse(await read("out/dev-latest.json"));
    assert.equal(out.cases.length, 3);
    assert.equal(out.cases.find((c: { id: string }) => c.id === "dev-scam-1").level, 1);

    assert.ok(!lines.join("\n").includes("FIXTURE-TEXT"), "printed case text");
    assert.match(lines.join("\n"), /misses 1\/2/);
  });

  it("fails when the set has no cases", async () => {
    await rm(path.join(evalDir, "cases", "dev"), { recursive: true });
    await mkdir(path.join(evalDir, "cases", "dev"));
    const { exitCode, lines } = await runEval({ evalDir, set: "dev", mode: "rules", notes: "", now: TODAY });
    assert.equal(exitCode, 1);
    assert.match(lines.join("\n"), /no cases/);
  });

  it("warns when the counts differ from the ones fixed at the split", async () => {
    await writeFile(path.join(evalDir, "split-counts.json"), JSON.stringify({ "sms/scam": { dev: 5, holdout: 5 } }));
    const { lines } = await runEval({ evalDir, set: "dev", mode: "rules", notes: "", now: TODAY });
    assert.match(lines.join("\n"), /warning: sms\/scam has 1 cases in dev, split-counts.json says 5/);
  });
});

describe("runEval --mode rules+claude", () => {
  it("stops with a clear error until the judge exists, and records nothing", async () => {
    const { exitCode, lines } = await runEval({ evalDir, set: "dev", mode: "rules+claude", notes: "", now: TODAY });
    assert.equal(exitCode, 1);
    assert.match(lines.join("\n"), /judge not available until #7/);
    await assert.rejects(read("results.jsonl"));
    assert.ok((await read("RESULTS.md")).endsWith(header));
  });

  it("uses the judge it is given", async () => {
    const judge: Judge = async () => ({ level: 2 });
    const { exitCode } = await runEval({ evalDir, set: "dev", mode: "rules+claude", notes: "", now: TODAY, judge });
    assert.equal(exitCode, 0);
    const r = JSON.parse((await read("results.jsonl")).trim());
    assert.equal(r.mode, "rules+claude");
    assert.equal(r.misses, 0);
    assert.equal(r.false_alarms, 1);
  });

  it("refuses a dev run once today's budget is used, without calling the judge", async () => {
    const used = [
      { ts: "2026-11-03T09:00:00+09:00", set: "dev", mode: "rules+claude" },
      { ts: "2026-11-03T10:00:00+09:00", set: "dev", mode: "rules+claude" },
    ];
    await writeFile(path.join(evalDir, "results.jsonl"), `${used.map((u) => JSON.stringify(u)).join("\n")}\n`);
    let called = 0;
    const judge: Judge = async () => {
      called++;
      return { level: 1 };
    };
    const { exitCode, lines } = await runEval({ evalDir, set: "dev", mode: "rules+claude", notes: "", now: TODAY, judge });
    assert.equal(exitCode, 1);
    assert.equal(called, 0);
    assert.match(lines.join("\n"), /budget/);
  });
});

describe("runEval --set holdout", () => {
  it("is locked until the author creates the unlock file", async () => {
    await writeCases("holdout");
    const { exitCode, lines } = await runEval({ evalDir, set: "holdout", mode: "rules", notes: "", now: TODAY });
    assert.equal(exitCode, 1);
    assert.match(lines.join("\n"), /locked/);
  });

  it("keeps per-case results out of eval/out once unlocked", async () => {
    await writeCases("holdout");
    await mkdir(path.join(repo, ".claude", "state"), { recursive: true });
    await writeFile(path.join(repo, ".claude", "state", "holdout.unlock"), "");
    const { exitCode, lines } = await runEval({ evalDir, set: "holdout", mode: "rules", notes: "final", now: TODAY });
    assert.equal(exitCode, 0);
    // Nothing per case under eval/out, whatever the file would be called.
    const out = await readdir(path.join(evalDir, "out")).catch(() => []);
    assert.deepEqual(out, []);
    assert.ok(!lines.join("\n").includes("dev-scam"), "printed case ids");
  });
});
