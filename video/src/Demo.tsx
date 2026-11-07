import React from "react";
import { AbsoluteFill, Sequence } from "remotion";
import {
  CALL_CONSULT_CAPTIONS,
  FOOTAGE,
  MOTHER_WORDS_CAPTIONS,
  SAFARI_CAPTIONS,
  SCENES,
  lengthOf,
  startOf,
} from "./timeline";
import { Captions, FootageSlot } from "./parts/common";
import { C } from "./parts/theme";
import { Opening } from "./scenes/Opening";
import { FamilyCard, FamilyResolve, SmsFallback } from "./scenes/FamilyScenes";
import { SmileDiagram } from "./scenes/Smile";
import { Accuracy, Observation } from "./scenes/Accuracy";
import { DevRecord, Limits } from "./scenes/Closing";

// 秒数は timeline.ts で決める。ここでは並べるだけ。
export const Demo: React.FC = () => (
  <AbsoluteFill style={{ backgroundColor: C.bg }}>
    <Sequence name="0 数字" from={startOf(SCENES.opening)} durationInFrames={lengthOf(SCENES.opening)}>
      <Opening />
    </Sequence>
    <Sequence name="0 母の言葉" from={startOf(SCENES.motherWords)} durationInFrames={lengthOf(SCENES.motherWords)}>
      <FootageSlot file={FOOTAGE.motherWords.file} what={FOOTAGE.motherWords.what} />
      <Captions cues={MOTHER_WORDS_CAPTIONS} />
    </Sequence>
    <Sequence name="15 電話のあとの相談" from={startOf(SCENES.callConsult)} durationInFrames={lengthOf(SCENES.callConsult)}>
      <FootageSlot file={FOOTAGE.callConsult.file} what={FOOTAGE.callConsult.what} />
      <Captions cues={CALL_CONSULT_CAPTIONS} />
    </Sequence>
    <Sequence name="52 家族のカード" from={startOf(SCENES.familyCard)} durationInFrames={lengthOf(SCENES.familyCard)}>
      <FamilyCard />
    </Sequence>
    <Sequence name="60 解決" from={startOf(SCENES.familyResolve)} durationInFrames={lengthOf(SCENES.familyResolve)}>
      <FamilyResolve />
    </Sequence>
    <Sequence name="72 Safari" from={startOf(SCENES.safari)} durationInFrames={lengthOf(SCENES.safari)}>
      <FootageSlot file={FOOTAGE.safari.file} what={FOOTAGE.safari.what} />
      <Captions cues={SAFARI_CAPTIONS} />
    </Sequence>
    <Sequence name="85 SMS" from={startOf(SCENES.sms)} durationInFrames={lengthOf(SCENES.sms)}>
      <FootageSlot file={FOOTAGE.sms.file} what={FOOTAGE.sms.what} fallback={<SmsFallback />} />
    </Sequence>
    <Sequence name="110 笑顔" from={startOf(SCENES.smile)} durationInFrames={lengthOf(SCENES.smile)}>
      <FootageSlot file={FOOTAGE.smile.file} what={FOOTAGE.smile.what} fallback={<SmileDiagram />} />
    </Sequence>
    <Sequence name="125 精度" from={startOf(SCENES.accuracy)} durationInFrames={lengthOf(SCENES.accuracy)}>
      <Accuracy />
    </Sequence>
    <Sequence name="140 母の利用" from={startOf(SCENES.observation)} durationInFrames={lengthOf(SCENES.observation)}>
      <Observation />
    </Sequence>
    <Sequence name="150 開発の記録" from={startOf(SCENES.devRecord)} durationInFrames={lengthOf(SCENES.devRecord)}>
      <DevRecord />
    </Sequence>
    <Sequence name="166 限界" from={startOf(SCENES.limits)} durationInFrames={lengthOf(SCENES.limits)}>
      <Limits />
    </Sequence>
  </AbsoluteFill>
);
