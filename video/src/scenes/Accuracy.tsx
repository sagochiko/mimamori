import React from "react";
import { AbsoluteFill, interpolate, useCurrentFrame, useVideoConfig } from "remotion";
import { DEV_EVAL, HOLDOUT } from "../numbers";
import { Note, Page, Rise } from "../parts/common";
import { C } from "../parts/theme";

type Row = { miss: string; missN: string; fp: string; fpN: string };

const Bar: React.FC<{ label: string; row: Row; color: string; delay: number }> = ({
  label,
  row,
  color,
  delay,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const grow = interpolate(frame, [delay * fps, (delay + 1) * fps], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  // 見逃し率を棒の長さにする(30%で最大の幅)
  const w = Math.max(6, (Number(row.miss) / 30) * 700) * grow;
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 28 }}>
      <div style={{ width: 300, fontSize: 40, fontWeight: 700 }}>{label}</div>
      <div style={{ width: 720 }}>
        <div style={{ height: 56, width: w, backgroundColor: color, borderRadius: 10 }} />
      </div>
      <div style={{ fontSize: 40, fontWeight: 700, width: 360 }}>
        見逃し {row.miss}%
        <span style={{ fontSize: 30, color: C.sub, fontWeight: 400 }}> ({row.missN})</span>
      </div>
    </div>
  );
};

// 125〜140秒 精度の数字
export const Accuracy: React.FC = () => (
  <Page>
    <AbsoluteFill style={{ padding: "90px 120px" }}>
      <Rise delay={0.2}>
        <div style={{ fontSize: 68, fontWeight: 900 }}>試験用の例文で見逃しを数えた</div>
        <div style={{ fontSize: 34, color: C.sub, marginTop: 10 }}>
          直すときに使う組(dev {DEV_EVAL.cases}件、{DEV_EVAL.date})
        </div>
      </Rise>
      <div style={{ display: "flex", flexDirection: "column", gap: 34, marginTop: 56 }}>
        <Bar label="規則だけ" row={DEV_EVAL.rules} color="#A9AEB8" delay={1} />
        <Bar label="規則と Claude" row={DEV_EVAL.claude} color={C.blue} delay={2} />
      </div>
      <Rise delay={3.5} style={{ marginTop: 34 }}>
        <div style={{ fontSize: 34, color: C.sub, lineHeight: 1.5 }}>
          本物を危ないとした誤報は 規則だけ {DEV_EVAL.rules.fp}%({DEV_EVAL.rules.fpN})、規則と
          Claude {DEV_EVAL.claude.fp}%({DEV_EVAL.claude.fpN})
          <br />
          誤報の4件は送金や認証コードの相談で、AI が案内せず家族に回す決まりのため
        </div>
      </Rise>
      <Rise delay={5} style={{ marginTop: 40 }}>
        {HOLDOUT ? (
          <div
            style={{
              border: `4px solid ${C.blue}`,
              borderRadius: 24,
              padding: "26px 36px",
              fontSize: 40,
              fontWeight: 700,
            }}
          >
            最後に1回だけ測った組(holdout {HOLDOUT.cases}件、{HOLDOUT.date})
            <br />
            規則だけ 見逃し {HOLDOUT.rules.miss}%({HOLDOUT.rules.missN}) 誤報{" "}
            {HOLDOUT.rules.fp}%({HOLDOUT.rules.fpN})
            <br />
            規則と Claude 見逃し {HOLDOUT.claude.miss}%({HOLDOUT.claude.missN}) 誤報{" "}
            {HOLDOUT.claude.fp}%({HOLDOUT.claude.fpN})
          </div>
        ) : (
          <div
            style={{
              border: "4px dashed #9CA3AF",
              borderRadius: 24,
              padding: "26px 36px",
              fontSize: 38,
              color: C.sub,
            }}
          >
            最後に測る組(holdout)の数字をここに入れる(2026年11月8日に1回だけ測る)
          </div>
        )}
      </Rise>
    </AbsoluteFill>
    <Note>出典 eval/RESULTS.md</Note>
  </Page>
);

// 140〜150秒 母の利用から直した1点と、母、妹、作者で試した観察
export const Observation: React.FC = () => (
  <Page>
    <AbsoluteFill style={{ padding: "110px 140px", gap: 48 }}>
      <Rise delay={0.2}>
        <div style={{ fontSize: 68, fontWeight: 900 }}>母が使って直したこと</div>
      </Rise>
      <Rise delay={0.8}>
        <div
          style={{
            border: `4px solid ${C.blue}`,
            borderRadius: 24,
            padding: "30px 40px",
            fontSize: 40,
            fontWeight: 700,
            lineHeight: 1.5,
          }}
        >
          知らないアプリの使い方の相談が家族に回っていた
          <br />
          → 「その画面を写真で見せてね」と聞き返す(#251)
          <br />
          使い方の相談を家族に回すのは案内のあとも困っているときだけ
        </div>
      </Rise>
      <Rise delay={1.6}>
        <div
          style={{
            border: `4px solid #9CA3AF`,
            borderRadius: 24,
            padding: "30px 40px",
            fontSize: 40,
                        lineHeight: 1.5,
          }}
        >
          2026年11月7日 母が1人で誘導なしに2回相談した(家族の側は作者の iPhone)
        </div>
      </Rise>
    </AbsoluteFill>
  </Page>
);
