import React from "react";
import { AbsoluteFill } from "remotion";
import { Page, Rise } from "../parts/common";
import { C } from "../parts/theme";

// 10〜15秒 母から家族に届いていた相談。撮影の代わりに、作者が覚えている母の相談を文字で出す
// (2026年11月8日に作者から聞いた。10月末のストレージの件が直近の例)。
const ITEMS = [
  "「ストレージがいっぱいって出てる」",
  "「広告のクリーナーアプリ、入れてもいいのかな」",
  "「アプリが増えて使い方が分からない」",
  "「この広告、本当にやってもいいの?」",
];

export const MotherWords: React.FC = () => (
  <Page>
    <AbsoluteFill style={{ padding: "120px 160px", justifyContent: "center" }}>
      <Rise delay={0}>
        <div style={{ fontSize: 46, fontWeight: 700, color: C.sub, marginBottom: 36 }}>
          母から家族に届いていた相談
        </div>
      </Rise>
      {ITEMS.map((t, i) => (
        <Rise key={t} delay={0.3 + i * 0.35}>
          <div style={{ fontSize: 62, fontWeight: 800, color: C.ink, lineHeight: 1.5 }}>・{t}</div>
        </Rise>
      ))}
    </AbsoluteFill>
  </Page>
);
