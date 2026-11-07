import React from "react";
import { Composition } from "remotion";
import { Demo } from "./Demo";
import { FPS, HEIGHT, TOTAL_SECONDS, WIDTH } from "./timeline";

export const RemotionRoot: React.FC = () => (
  <Composition
    id="Demo"
    component={Demo}
    durationInFrames={TOTAL_SECONDS * FPS}
    fps={FPS}
    width={WIDTH}
    height={HEIGHT}
  />
);
