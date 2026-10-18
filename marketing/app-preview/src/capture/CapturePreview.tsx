import React from "react";
import { AbsoluteFill, OffthreadVideo, interpolate, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { F, FPS } from "../theme";

export type Caption = { text: string; from: number; to: number };

export type CaptureProps = { src: string; captions: Caption[]; bottom: number; size: number };

// App Review (2.3.4) accepts only full-screen captures of the app, optionally with text overlays:
// the recording fills the frame edge to edge, and nothing but a caption is drawn on top of it.
export const CapturePreview: React.FC<CaptureProps> = ({ src, captions, bottom, size }) => {
  const f = useCurrentFrame();
  const { width } = useVideoConfig();
  const t = f / FPS;
  const active = captions.find((c) => t >= c.from && t < c.to);
  const fade = active
    ? Math.min(interpolate(t, [active.from, active.from + 0.25], [0, 1], { extrapolateRight: "clamp" }),
        interpolate(t, [active.to - 0.25, active.to], [1, 0], { extrapolateLeft: "clamp" }))
    : 0;
  return (
    <AbsoluteFill style={{ background: "#000" }}>
      <OffthreadVideo src={staticFile(src)} style={{ width: "100%", height: "100%" }} muted />
      {active && (
        <div
          style={{
            position: "absolute",
            left: 0,
            right: 0,
            bottom,
            display: "flex",
            justifyContent: "center",
            opacity: fade,
            transform: `translateY(${(1 - fade) * 12}px)`,
          }}
        >
          <div
            style={{
              maxWidth: width * 0.86,
              padding: `${size * 0.45}px ${size * 0.9}px`,
              borderRadius: size * 1.4,
              background: "rgba(10,14,28,0.86)",
              boxShadow: "0 10px 40px rgba(0,0,0,0.25)",
              color: "#fff",
              fontFamily: F.display,
              fontWeight: 700,
              fontSize: size,
              lineHeight: 1.15,
              textAlign: "center",
            }}
          >
            {active.text}
          </div>
        </div>
      )}
    </AbsoluteFill>
  );
};
