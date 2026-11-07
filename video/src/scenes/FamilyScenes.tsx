import React from "react";
import { AbsoluteFill } from "remotion";
import { TOUR } from "../timeline";
import { Note, Page, PhoneClip, Rise } from "../parts/common";
import { C } from "../parts/theme";

const SideBySide: React.FC<{
  trimBeforeSec: number;
  playbackRate?: number;
  title: React.ReactNode;
  sub?: React.ReactNode;
  note?: string;
}> = ({ trimBeforeSec, playbackRate, title, sub, note }) => (
  <Page>
    <AbsoluteFill
      style={{
        flexDirection: "row",
        alignItems: "center",
        padding: "0 140px",
        gap: 110,
      }}
    >
      <PhoneClip
        file={TOUR.file}
        trimBeforeSec={trimBeforeSec}
        playbackRate={playbackRate}
        height={880}
      />
      <div style={{ display: "flex", flexDirection: "column", gap: 36, flex: 1 }}>
        <Rise delay={0.3}>
          <div style={{ fontSize: 76, fontWeight: 900, lineHeight: 1.3 }}>{title}</div>
        </Rise>
        {sub ? (
          <Rise delay={1.2}>
            <div style={{ fontSize: 46, color: C.sub, lineHeight: 1.5 }}>{sub}</div>
          </Rise>
        ) : null}
      </div>
    </AbsoluteFill>
    {note ? <Note left={680}>{note}</Note> : null}
  </Page>
);

// 52〜60秒 家族のカード
export const FamilyCard: React.FC = () => (
  <SideBySide
    trimBeforeSec={TOUR.familyCardFrom}
    playbackRate={0.4}
    title={
      <>
        家族全員の iPhone に
        <br />
        カードが届く
      </>
    }
    sub={
      <>
        何の相談でどれだけ危ないかが分かる
        <br />
        母の言葉はカードに写さない
      </>
    }
    note="体験モードの画面(試験用の相談)"
  />
);

// 60〜72秒 家族が電話して解決を押す
export const FamilyResolve: React.FC = () => (
  <SideBySide
    trimBeforeSec={TOUR.resolveFrom}
    title={
      <>
        母と話した家族が
        <br />
        「解決」を押す
      </>
    }
    sub="ほかの家族にも解決が伝わる"
    note="体験モードの画面(試験用の相談)"
  />
);

// 85〜110秒 SMS(撮影が無いときの代わり)
export const SmsFallback: React.FC = () => (
  <SideBySide
    trimBeforeSec={TOUR.smsFrom}
    title={
      <>
        知らない相手の SMS も
        <br />
        母の代わりに見る
      </>
    }
    sub={
      <>
        「家族には知らせないで」という文には従わない
        <br />
        詐欺の印として危なさを上げる
      </>
    }
    note="体験モードの画面(試験用の SMS)"
  />
);
