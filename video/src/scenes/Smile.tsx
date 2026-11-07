import React from "react";
import { AbsoluteFill, interpolate, useCurrentFrame, useVideoConfig } from "remotion";
import { Page, Rise } from "../parts/common";
import { C } from "../parts/theme";

// 顔の写真は使わず、図で見せる(撮影を置けばそちらが入る)
const Face: React.FC<{ size: number; color: string }> = ({ size, color }) => (
  <svg width={size} height={size} viewBox="0 0 100 100">
    <circle cx="50" cy="50" r="46" fill={color} />
    <circle cx="35" cy="42" r="6" fill={C.ink} />
    <circle cx="65" cy="42" r="6" fill={C.ink} />
    <path
      d="M28 60 Q50 82 72 60"
      stroke={C.ink}
      strokeWidth="6"
      fill="none"
      strokeLinecap="round"
    />
  </svg>
);

const Phone: React.FC<{ label: string; children: React.ReactNode }> = ({
  label,
  children,
}) => (
  <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 20 }}>
    <div
      style={{
        width: 300,
        height: 600,
        borderRadius: 54,
        border: `12px solid ${C.ink}`,
        backgroundColor: C.card,
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        gap: 28,
      }}
    >
      {children}
    </div>
    <div style={{ fontSize: 40, fontWeight: 700, color: C.sub }}>{label}</div>
  </div>
);

const Arrow: React.FC<{ progress: number; color: string; toRight: boolean }> = ({
  progress,
  color,
  toRight,
}) => {
  const len = 400 * progress;
  const x1 = toRight ? 10 : 410;
  const x2 = toRight ? 10 + len : 410 - len;
  const dir = toRight ? 1 : -1;
  return (
    <svg width={420} height={40} viewBox="0 0 420 40" style={{ opacity: progress > 0 ? 1 : 0 }}>
      <line x1={x1} y1={20} x2={x2} y2={20} stroke={color} strokeWidth={10} strokeLinecap="round" />
      <path
        d={`M${x2 - dir * 22} 4 L${x2 + dir * 4} 20 L${x2 - dir * 22} 36`}
        stroke={color}
        strokeWidth={10}
        fill="none"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
};

export const SmileDiagram: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const go = interpolate(frame, [1.5 * fps, 3.5 * fps], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const back = interpolate(frame, [6 * fps, 8 * fps], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  return (
    <Page>
      <AbsoluteFill style={{ padding: "100px 140px" }}>
        <Rise delay={0.2}>
          <div style={{ fontSize: 76, fontWeight: 900 }}>毎朝の笑顔が家族に届く</div>
        </Rise>
        <Rise delay={5.5}>
          <div style={{ fontSize: 46, color: C.sub, marginTop: 16 }}>
            家族も笑顔で返す
          </div>
        </Rise>
        <div
          style={{
            position: "absolute",
            left: 0,
            right: 0,
            bottom: 70,
            display: "flex",
            justifyContent: "center",
            alignItems: "center",
            gap: 120,
          }}
        >
          <Phone label="母">
            <Face size={170} color="#FFD66B" />
            <div style={{ opacity: back, display: "flex", gap: 12 }}>
              <Face size={80} color="#9FD3FF" />
              <Face size={80} color="#B8E6B0" />
            </div>
          </Phone>
          <div style={{ display: "flex", flexDirection: "column", gap: 40, width: 420 }}>
            <Arrow progress={go} color={C.blue} toRight />
            <Arrow progress={back} color="#4FA86A" toRight={false} />
          </div>
          <Phone label="家族">
            <div style={{ opacity: go }}>
              <Face size={170} color="#FFD66B" />
            </div>
            <div style={{ opacity: back }}>
              <Face size={80} color="#9FD3FF" />
            </div>
          </Phone>
        </div>
      </AbsoluteFill>
    </Page>
  );
};
