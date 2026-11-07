import React from "react";
import { AbsoluteFill } from "remotion";
import { NPA } from "../numbers";
import { Page, Rise } from "../parts/common";
import { C } from "../parts/theme";

// 0〜10秒 被害額の数字と出典
export const Opening: React.FC = () => (
  <Page>
    <AbsoluteFill style={{ padding: "110px 140px", gap: 0 }}>
      <Rise delay={0.2}>
        <div style={{ fontSize: 48, fontWeight: 700, color: C.sub }}>
          2025年の特殊詐欺の被害額
        </div>
        <div style={{ fontSize: 150, fontWeight: 900, letterSpacing: -2 }}>
          {NPA.totalOku}
          <span style={{ fontSize: 80 }}>億円</span>
        </div>
      </Rise>
      <Rise delay={2.2} style={{ marginTop: 40 }}>
        <div style={{ fontSize: 56, fontWeight: 700 }}>
          そのうち
          <span style={{ color: C.red, fontSize: 96, fontWeight: 900 }}> 約7割 </span>
          がニセ警察詐欺
        </div>
        <div style={{ fontSize: 48, color: C.sub, marginTop: 12 }}>
          {NPA.fakePoliceOku}億円({NPA.share}%)
        </div>
      </Rise>
      <Rise delay={4.6} style={{ marginTop: 56 }}>
        <div
          style={{
            fontSize: 60,
            fontWeight: 900,
            color: C.blue,
          }}
        >
          離れて住む母の iPhone を家族が代わりに見守る
        </div>
      </Rise>
      <Rise delay={1} style={{ position: "absolute", left: 140, bottom: 90 }}>
        <div style={{ fontSize: 28, color: C.sub }}>
          出典 警察庁 確定値({NPA.published})
        </div>
        <div style={{ fontSize: 26, color: C.sub, fontFamily: "Menlo, monospace" }}>
          {NPA.url}
        </div>
      </Rise>
    </AbsoluteFill>
  </Page>
);
