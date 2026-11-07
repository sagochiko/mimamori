import React from "react";
import { AbsoluteFill } from "remotion";
import { DEV_RECORD } from "../numbers";
import { Note, Page, Rise } from "../parts/common";
import { C } from "../parts/theme";

const Step: React.FC<{ name: string; role: string; color: string }> = ({
  name,
  role,
  color,
}) => (
  <div
    style={{
      backgroundColor: "#24262D",
      border: `3px solid ${color}`,
      borderRadius: 22,
      padding: "22px 26px",
      width: 300,
      textAlign: "center",
    }}
  >
    <div style={{ fontSize: 40, fontWeight: 700 }}>{name}</div>
    <div style={{ fontSize: 26, color: "#A0A4AE", marginTop: 6 }}>{role}</div>
  </div>
);

const Arrow = () => <div style={{ fontSize: 44, color: "#6B7080" }}>→</div>;

const Stat: React.FC<{ n: number; unit: string; label: string }> = ({ n, unit, label }) => (
  <div style={{ width: 380 }}>
    <div style={{ fontSize: 84, fontWeight: 900 }}>
      {n}
      <span style={{ fontSize: 40 }}>{unit}</span>
    </div>
    <div style={{ fontSize: 32, color: "#C9CDD6" }}>{label}</div>
  </div>
);

// 150〜166秒 Claude Code での開発の記録
export const DevRecord: React.FC = () => (
  <Page dark>
    <AbsoluteFill style={{ padding: "90px 120px" }}>
      <Rise delay={0.2}>
        <div style={{ fontSize: 68, fontWeight: 900 }}>Claude Code で6日かけて作った</div>
        <div style={{ fontSize: 36, color: "#C9CDD6", marginTop: 12 }}>
          Issue ごとに書く役と確かめる役とレビューする役を分けた
        </div>
      </Rise>
      <Rise delay={1.2} style={{ marginTop: 50 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 22 }}>
          <Step name="実装役" role="テストから書く" color="#5EA1FF" />
          <Arrow />
          <Step name="検証役" role="ビルドと画面" color="#6FD39A" />
          <Arrow />
          <Step name="レビュー役" role="別の文脈で読む" color="#F2B45A" />
          <Arrow />
          <Step name="マージ" role="結果を PR に残す" color="#A0A4AE" />
        </div>
      </Rise>
      <Rise delay={3} style={{ marginTop: 60 }}>
        <div style={{ display: "flex", gap: 20 }}>
          <Stat n={DEV_RECORD.reviewer} unit="回" label="レビュー役を起動" />
          <Stat n={DEV_RECORD.implementer} unit="回" label="実装役を起動" />
          <Stat n={DEV_RECORD.mergedPrs} unit="件" label="マージした PR" />
          <Stat n={DEV_RECORD.hookStops} unit="回" label="フックが止めるか作者に確かめた操作" />
        </div>
      </Rise>
      <Rise delay={8} style={{ marginTop: 50 }}>
        <div style={{ fontSize: 38, lineHeight: 1.5 }}>
          マイクを初めて押すとアプリが落ちた。
          <br />
          iPhone の落ちた記録を Claude Code が読んで原因まで切り分けた(#57)
        </div>
      </Rise>
    </AbsoluteFill>
    <Note dark>{DEV_RECORD.period}のフックの記録(docs/claude-usage.md)</Note>
  </Page>
);

// 166〜178秒 守れる範囲の限界
export const Limits: React.FC = () => (
  <Page>
    <AbsoluteFill style={{ padding: "110px 140px" }}>
      <Rise delay={0.2}>
        <div style={{ fontSize: 76, fontWeight: 900 }}>守れる範囲には限りがある</div>
      </Rise>
      <div style={{ display: "flex", flexDirection: "column", gap: 30, marginTop: 56 }}>
        <Rise delay={1}>
          <div style={{ fontSize: 50, fontWeight: 700 }}>
            電話と LINE の中身はアプリから見えない
          </div>
        </Rise>
        <Rise delay={2.2}>
          <div style={{ fontSize: 50, fontWeight: 700, color: C.red }}>
            だから母が話してくれることが要る
          </div>
        </Rise>
        <Rise delay={3.4}>
          <div style={{ fontSize: 42, color: C.sub }}>Safari 以外のブラウザは見ていない</div>
        </Rise>
        <Rise delay={4.2}>
          <div style={{ fontSize: 42, color: C.sub }}>
            どの経路でも「安全です」とは言わない
          </div>
        </Rise>
      </div>
      <Rise delay={6.5} style={{ position: "absolute", left: 140, bottom: 90 }}>
        <div style={{ fontSize: 64, fontWeight: 900 }}>みまもり</div>
        <div style={{ fontSize: 32, color: C.sub, fontFamily: "Menlo, monospace" }}>
          github.com/sagochiko/mimamori
        </div>
      </Rise>
    </AbsoluteFill>
  </Page>
);
