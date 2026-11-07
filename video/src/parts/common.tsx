import React from "react";
import {
  AbsoluteFill,
  Easing,
  getStaticFiles,
  interpolate,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { Video } from "@remotion/media";
import { C, fontFamily } from "./theme";

export const hasStatic = (file: string) =>
  getStaticFiles().some((f) => f.name === file);

// 場面の頭と終わりで薄く出し入れする
export const useFade = (inSec = 0.5, outSec = 0.4) => {
  const frame = useCurrentFrame();
  const { fps, durationInFrames } = useVideoConfig();
  return interpolate(
    frame,
    [0, inSec * fps, durationInFrames - outSec * fps, durationInFrames],
    [0, 1, 1, 0],
    {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
      easing: Easing.bezier(0.16, 1, 0.3, 1),
    },
  );
};

export const Rise: React.FC<{
  delay?: number;
  children: React.ReactNode;
  style?: React.CSSProperties;
}> = ({ delay = 0, children, style }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return (
    <div
      style={{
        opacity: interpolate(frame, [delay * fps, (delay + 0.6) * fps], [0, 1], {
          extrapolateLeft: "clamp",
          extrapolateRight: "clamp",
        }),
        translate: interpolate(
          frame,
          [delay * fps, (delay + 0.6) * fps],
          ["0px 24px", "0px 0px"],
          {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
            easing: Easing.bezier(0.16, 1, 0.3, 1),
          },
        ),
        ...style,
      }}
    >
      {children}
    </div>
  );
};

export const Page: React.FC<{
  children: React.ReactNode;
  dark?: boolean;
}> = ({ children, dark }) => {
  const opacity = useFade();
  return (
    <AbsoluteFill
      style={{
        backgroundColor: dark ? C.dark : C.bg,
        color: dark ? "#fff" : C.ink,
        fontFamily,
      }}
    >
      <AbsoluteFill style={{ opacity }}>{children}</AbsoluteFill>
    </AbsoluteFill>
  );
};

// 画面の下の字幕。秒は場面の始まりから。
export const Captions: React.FC<{
  cues: readonly { from: number; to: number; text: string }[];
}> = ({ cues }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const t = frame / fps;
  const cue = cues.find((c) => t >= c.from && t < c.to);
  if (!cue) return null;
  return (
    <AbsoluteFill
      style={{ justifyContent: "flex-end", alignItems: "center", paddingBottom: 70 }}
    >
      <div
        style={{
          fontFamily,
          fontWeight: 700,
          fontSize: 52,
          color: "#fff",
          backgroundColor: "rgba(16,17,20,0.82)",
          padding: "18px 40px",
          borderRadius: 18,
          maxWidth: 1600,
          textAlign: "center",
        }}
      >
        {cue.text}
      </div>
    </AbsoluteFill>
  );
};

// 撮影を入れる枠。ファイルがあれば流し、無ければ「何を撮るか」を出す。
export const FootageSlot: React.FC<{
  file: string;
  what: string;
  fallback?: React.ReactNode;
}> = ({ file, what, fallback }) => {
  if (hasStatic(file)) {
    return (
      <AbsoluteFill style={{ backgroundColor: "#000" }}>
        <Video
          src={staticFile(file)}
          style={{ width: "100%", height: "100%", objectFit: "contain" }}
        />
      </AbsoluteFill>
    );
  }
  if (fallback) return <>{fallback}</>;
  return <Placeholder file={file} what={what} />;
};

export const Placeholder: React.FC<{ file: string; what: string }> = ({
  file,
  what,
}) => (
  <AbsoluteFill
    style={{
      backgroundColor: "#2A2C33",
      justifyContent: "center",
      alignItems: "center",
      fontFamily,
      color: "#fff",
    }}
  >
    <div
      style={{
        border: "4px dashed #8E93A0",
        borderRadius: 32,
        padding: "56px 72px",
        width: 1500,
        display: "flex",
        flexDirection: "column",
        gap: 28,
      }}
    >
      <div style={{ fontSize: 40, color: "#C9CDD6", fontWeight: 700 }}>
        ここに母の iPhone の撮影
      </div>
      <div style={{ fontSize: 48, fontWeight: 700, lineHeight: 1.45 }}>{what}</div>
      <div
        style={{
          fontSize: 32,
          color: "#9CA3AF",
          fontFamily: "Menlo, monospace",
        }}
      >
        video/public/{file}
      </div>
      <PlaceholderLength />
    </div>
  </AbsoluteFill>
);

const PlaceholderLength: React.FC = () => {
  const { durationInFrames, fps } = useVideoConfig();
  return (
    <div style={{ fontSize: 32, color: "#9CA3AF" }}>
      この枠は{Math.round(durationInFrames / fps)}秒
    </div>
  );
};

// 縦長の画面の録画を、角の丸い枠に入れて出す
export const PhoneClip: React.FC<{
  file: string;
  trimBeforeSec: number;
  playbackRate?: number;
  height?: number;
}> = ({ file, trimBeforeSec, playbackRate = 1, height = 900 }) => {
  const { fps } = useVideoConfig();
  const width = Math.round((height * 1206) / 2622);
  return (
    <div
      style={{
        width: width + 24,
        height: height + 24,
        borderRadius: 64,
        backgroundColor: "#111",
        padding: 12,
        boxShadow: "0 30px 80px rgba(0,0,0,0.25)",
      }}
    >
      <div
        style={{
          width,
          height,
          borderRadius: 52,
          overflow: "hidden",
          backgroundColor: "#fff",
        }}
      >
        {hasStatic(file) ? (
          <Video
            src={staticFile(file)}
            trimBefore={Math.round(trimBeforeSec * fps)}
            playbackRate={playbackRate}
            muted
            style={{ width, height, objectFit: "cover" }}
          />
        ) : (
          <div
            style={{
              width,
              height,
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              fontSize: 28,
              color: C.sub,
              padding: 30,
              textAlign: "center",
            }}
          >
            npm run assets で体験モードの録画を写す
          </div>
        )}
      </div>
    </div>
  );
};

export const Note: React.FC<{
  children: React.ReactNode;
  dark?: boolean;
  left?: number;
}> = ({ children, dark, left = 120 }) => (
  <div
    style={{
      position: "absolute",
      left,
      bottom: 56,
      fontSize: 26,
      color: dark ? "#A0A4AE" : C.sub,
    }}
  >
    {children}
  </div>
);
