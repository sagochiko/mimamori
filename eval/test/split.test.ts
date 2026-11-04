// eval/split.ts on fixture files in a temporary folder. It never touches the real pool.
// Run: cd server && npx tsx --test ../eval/test/*.test.ts

import assert from "node:assert/strict";
import { mkdir, mkdtemp, readdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, it } from "node:test";
import { planSplit } from "../lib/split-plan";
import { splitPool } from "../split";

let tmp: string;
let dirs: { pool: string; dev: string; holdout: string; countsFile: string };

function caseLine(id: string, source: string, isScam: boolean): string {
  return JSON.stringify({
    id,
    source,
    sender: null,
    domain: null,
    text: `fixture text ${id}`,
    url: null,
    expected_level: isScam ? 1 : null,
    is_scam: isScam,
    note: "self-written",
  });
}

async function pattern(name: string, source: string, isScam: boolean, count: number) {
  const lines = Array.from({ length: count }, (_, i) => caseLine(`${name}-${i}`, source, isScam));
  await writeFile(path.join(dirs.pool, `${name}.jsonl`), `${lines.join("\n")}\n`);
}

const jsonl = async (dir: string) => (await readdir(dir)).filter((f) => f.endsWith(".jsonl")).sort();

beforeEach(async () => {
  tmp = await mkdtemp(path.join(tmpdir(), "mm-split-"));
  dirs = {
    pool: path.join(tmp, "cases", "pool"),
    dev: path.join(tmp, "cases", "dev"),
    holdout: path.join(tmp, "cases", "holdout"),
    countsFile: path.join(tmp, "split-counts.json"),
  };
  for (const dir of [dirs.pool, dirs.dev, dirs.holdout]) await mkdir(dir, { recursive: true });
  await writeFile(path.join(dirs.pool, ".gitkeep"), "");
});

afterEach(async () => {
  await rm(tmp, { recursive: true, force: true });
});

describe("splitPool", () => {
  it("moves whole pattern files into dev and holdout and prints the counts", async () => {
    await pattern("sms-scam-a", "sms", true, 3);
    await pattern("sms-scam-b", "sms", true, 2);
    await pattern("sms-scam-c", "sms", true, 1);
    await pattern("sms-genuine-a", "sms", false, 2);
    await pattern("sms-genuine-b", "sms", false, 2);
    await pattern("consult-injection", "consult", true, 2);
    const before = await readFile(path.join(dirs.pool, "sms-scam-a.jsonl"), "utf8");

    const { lines } = await splitPool(dirs);

    assert.deepEqual(await jsonl(dirs.pool), []);
    const dev = await jsonl(dirs.dev);
    const holdout = await jsonl(dirs.holdout);
    assert.equal(dev.length + holdout.length, 6);
    assert.deepEqual(dev.filter((f) => holdout.includes(f)), []);
    const moved = dev.includes("sms-scam-a.jsonl") ? dirs.dev : dirs.holdout;
    assert.equal(await readFile(path.join(moved, "sms-scam-a.jsonl"), "utf8"), before);
    // .gitkeep and anything that is not a pattern file stay.
    assert.deepEqual(await readdir(dirs.pool), [".gitkeep"]);

    const out = lines.join("\n");
    assert.match(out, /sms\/scam\s+dev 3 \(\d files\)\s+holdout 3 \(\d files\)/);
    assert.match(out, /sms\/genuine\s+dev 2 \(1 files\)\s+holdout 2 \(1 files\)/);
    // Holdout file names are not printed; dev ones are, for the README.
    for (const name of holdout) assert.ok(!out.includes(name), `printed holdout file ${name}`);
    assert.ok(!out.includes("fixture text"), "printed case text");

    const counts = JSON.parse(await readFile(dirs.countsFile, "utf8"));
    assert.deepEqual(counts["sms/scam"], { dev: 3, holdout: 3 });
    assert.deepEqual(counts["consult/scam"], { dev: 0, holdout: 2 });
  });

  it("adds a later batch to the recorded counts", async () => {
    await pattern("sms-scam-a", "sms", true, 2);
    await splitPool(dirs);
    await pattern("sms-scam-c", "sms", true, 2);
    await splitPool(dirs);
    const counts = JSON.parse(await readFile(dirs.countsFile, "utf8"));
    // Each batch holds one file of the group, so each name decides its side (a to dev, c to holdout).
    assert.deepEqual(counts["sms/scam"], { dev: 2, holdout: 2 });
  });

  it("sends a group of one file to dev or holdout by its name, not always to the holdout", () => {
    const sideOf = (name: string) =>
      planSplit([{ name, source: "sms", isScam: true, count: 3 }]).assignments[0]!.set;
    const names = ["sms-scam-a.jsonl", "sms-scam-b.jsonl", "sms-scam-c.jsonl", "sms-scam-d.jsonl"];
    assert.deepEqual(names.map(sideOf), ["dev", "dev", "holdout", "holdout"]);
    // The same name always lands on the same side.
    assert.deepEqual(names.map(sideOf), ["dev", "dev", "holdout", "holdout"]);
  });

  it("says so and moves nothing when the pool is empty", async () => {
    const { lines } = await splitPool(dirs);
    assert.match(lines.join("\n"), /pool is empty/);
  });

  it("moves nothing on a dry run", async () => {
    await pattern("sms-scam-a", "sms", true, 2);
    await pattern("sms-scam-b", "sms", true, 2);
    const { lines } = await splitPool({ ...dirs, dryRun: true });
    assert.deepEqual(await jsonl(dirs.pool), ["sms-scam-a.jsonl", "sms-scam-b.jsonl"]);
    assert.match(lines.join("\n"), /dry run/);
  });

  for (const [label, setup, message] of [
    [
      "a file that mixes scam and genuine cases",
      async () => {
        await writeFile(
          path.join(dirs.pool, "sms-mixed.jsonl"),
          `${caseLine("m1", "sms", true)}\n${caseLine("m2", "sms", false)}\n`,
        );
      },
      /sms-mixed\.jsonl.*one path and one of scam or genuine/,
    ],
    [
      "the same id in two files",
      async () => {
        await writeFile(path.join(dirs.pool, "sms-scam-x.jsonl"), `${caseLine("dup", "sms", true)}\n`);
        await writeFile(path.join(dirs.pool, "sms-scam-y.jsonl"), `${caseLine("dup", "sms", true)}\n`);
      },
      /duplicate id dup/,
    ],
    [
      "a name already in dev",
      async () => {
        await pattern("sms-scam-a", "sms", true, 1);
        await writeFile(path.join(dirs.dev, "sms-scam-a.jsonl"), `${caseLine("old", "sms", true)}\n`);
      },
      /already exists/,
    ],
    [
      "a broken line",
      async () => {
        await writeFile(path.join(dirs.pool, "sms-scam-z.jsonl"), `${caseLine("ok", "sms", true)}\n{broken\n`);
      },
      /sms-scam-z\.jsonl:2/,
    ],
  ] as const) {
    it(`refuses ${label} and moves nothing`, async () => {
      await pattern("sms-scam-good", "sms", true, 2);
      await setup();
      const poolBefore = await jsonl(dirs.pool);
      await assert.rejects(splitPool(dirs), message);
      assert.deepEqual(await jsonl(dirs.pool), poolBefore);
    });
  }
});
