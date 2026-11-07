// ナレーションの mp3 を Amazon Polly で作り直し、場面の枠に収まるかを確かめる。
// 使い方: AWS_PROFILE=<プロファイル> npm run narration
// 1つだけ作り直すときは、id を引数に渡す(npm run narration -- 06-sms)。
import { execFileSync } from "node:child_process";
import { mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { NARRATION, RATE, VOICE } from "../src/narration.ts";
import { SCENES } from "../src/timeline.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const outDir = join(root, "public", "narration");
mkdirSync(outDir, { recursive: true });

if (!process.env.AWS_PROFILE) {
  console.error("AWS_PROFILE を指定する(例 AWS_PROFILE=<プロファイル> npm run narration)");
  process.exit(1);
}

const only = process.argv.slice(2);
let chars = 0;
let failed = false;
const rows = [];

for (const n of NARRATION) {
  const file = join(outDir, `${n.id}.mp3`);
  const ssml = `<speak><prosody rate="${RATE}">${n.ssml}</prosody></speak>`;
  if (only.length === 0 || only.includes(n.id)) {
    execFileSync(
      "aws",
      [
        "polly",
        "synthesize-speech",
        "--engine",
        "neural",
        "--language-code",
        "ja-JP",
        "--voice-id",
        VOICE,
        "--output-format",
        "mp3",
        "--text-type",
        "ssml",
        "--text",
        ssml,
        file,
      ],
      { stdio: ["ignore", "ignore", "inherit"] },
    );
    chars += ssml.length;
  }
  const sec = Number(
    execFileSync("ffprobe", [
      "-v",
      "error",
      "-show_entries",
      "format=duration",
      "-of",
      "csv=p=0",
      file,
    ])
      .toString()
      .trim(),
  );
  const scene = SCENES[n.scene];
  const room = scene.to - scene.from - n.at;
  const ok = sec <= room - 0.3;
  if (!ok) failed = true;
  rows.push(
    `${n.id}\t${scene.from}〜${scene.to}秒\t+${n.at}秒から\t${sec.toFixed(2)}秒\t空き${room.toFixed(1)}秒\t${ok ? "収まる" : "はみ出す"}`,
  );
}

console.log(rows.join("\n"));
console.log(`送った字数(SSML の印を含む) ${chars}`);
if (failed) {
  console.error("場面の枠からはみ出すナレーションがある。文を削るか RATE を上げる");
  process.exit(1);
}
