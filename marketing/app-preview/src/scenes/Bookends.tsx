import React from "react";
import { AbsoluteFill, Img, interpolate, staticFile, useVideoConfig } from "remotion";
import { ease, OUT, pop, useFmt, useSceneFrame } from "../components/kit";
import { TemplateWall } from "../components/TemplateWall";
import { C, F } from "../theme";

// logo.svg is 451x73; the mark is the first ~15% of it.
const MARK = 0.155;

export const Logo: React.FC<{ f: number; y: number; width: number }> = ({ f, y, width }) => {
  const { width: W } = useVideoConfig();
  const h = (width * 73) / 451;
  const k = pop(f, 0, 10, 160);
  const spin = interpolate(k, [0, 1], [-120, 0]);
  const reveal = ease(f, [10, 30], [0, 1], OUT);
  const glow = interpolate(f, [8, 20, 60], [0, 1, 0.35], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const src = staticFile("logo.svg");
  const left = (W - width) / 2;
  return (
    <div style={{ position: "absolute", left, top: y, width, height: h }}>
      <div
        style={{
          position: "absolute",
          inset: 0,
          clipPath: `inset(-20% ${(1 - MARK) * 100}% -20% -20%)`,
          transform: `translateX(${(1 - reveal) * width * 0.42}px) rotate(${spin}deg) scale(${k})`,
          transformOrigin: `${(MARK / 2) * 100}% 50%`,
          filter: `drop-shadow(0 0 ${30 * glow}px rgba(6,115,236,${glow}))`,
        }}
      >
        <Img src={src} style={{ width, height: h }} />
      </div>
      <div
        style={{
          position: "absolute",
          inset: 0,
          clipPath: `inset(-20% ${(1 - reveal) * (1 - MARK) * 100}% -20% ${MARK * 100}%)`,
          transform: `translateX(${(1 - reveal) * width * 0.42}px)`,
        }}
      >
        <Img src={src} style={{ width, height: h }} />
      </div>
    </div>
  );
};

const Tagline: React.FC<{ f: number; start: number; text: string; top: number; size: number }> = ({ f, start, text, top, size }) => (
  <div
    style={{
      position: "absolute",
      top,
      left: 0,
      right: 0,
      textAlign: "center",
      fontFamily: F.display,
      fontWeight: 600,
      fontSize: size,
      color: C.dim,
      letterSpacing: ease(f, [start, start + 20], [1, size * 0.18]),
      opacity: ease(f, [start, start + 12], [0, 1]),
    }}
  >
    {text}
  </div>
);

const Wall: React.FC<{ f: number }> = ({ f }) => {
  const fmt = useFmt();
  const h = fmt === "phone" ? 200 : 170;
  return (
    <AbsoluteFill style={{ overflow: "hidden", opacity: ease(f, [0, 20], [0, 0.55]) }}>
      <div style={{ position: "absolute", left: "-30%", top: "-25%", width: "160%", transform: "perspective(1400px) rotateX(28deg) rotateZ(-14deg)", transformOrigin: "50% 0" }}>
        <TemplateWall rows={fmt === "phone" ? 9 : 6} h={h} speed={2.2} />
      </div>
      <AbsoluteFill style={{ background: `radial-gradient(55% 45% at 50% 45%, ${C.bg}F0 20%, ${C.bg}80 60%, transparent 100%)` }} />
    </AbsoluteFill>
  );
};

export const Intro: React.FC = () => {
  const f = useSceneFrame();
  const { height } = useVideoConfig();
  const fmt = useFmt();
  const lw = fmt === "phone" ? 760 : fmt === "pad" ? 1100 : 1180;
  const lh = (lw * 73) / 451;
  const y = height * 0.44 - lh / 2;
  return (
    <AbsoluteFill>
      <Wall f={f} />
      <Logo f={f} y={y} width={lw} />
      <Tagline f={f} start={36} text={fmt === "phone" ? "APP STORE SCREENSHOTS" : "APP STORE SCREENSHOTS, BEAUTIFULLY DONE"} top={y + lh + (fmt === "phone" ? 60 : 70)} size={fmt === "phone" ? 34 : 34} />
    </AbsoluteFill>
  );
};

const STEPS = ["Design it.", "Localize it.", "Ship it."];

export const Outro: React.FC = () => {
  const f = useSceneFrame();
  const { height } = useVideoConfig();
  const fmt = useFmt();
  const lw = fmt === "phone" ? 720 : fmt === "pad" ? 980 : 1040;
  const lh = (lw * 73) / 451;
  const y = height * (fmt === "phone" ? 0.36 : 0.3) - lh / 2;
  const active = f < 28 ? -1 : f < 38 ? 0 : f < 48 ? 1 : 2;
  return (
    <AbsoluteFill>
      <Wall f={f + 60} />
      <Logo f={f + 2} y={y} width={lw} />
      <div
        style={{
          position: "absolute",
          top: y + lh + (fmt === "phone" ? 110 : 90),
          left: 0,
          right: 0,
          display: "flex",
          flexDirection: fmt === "phone" ? "column" : "row",
          alignItems: "center",
          justifyContent: "center",
          gap: fmt === "phone" ? 20 : 18,
          opacity: ease(f, [20, 30], [0, 1]),
        }}
      >
        {STEPS.map((s, i) => {
          const on = i === active;
          return (
            <span
              key={s}
              style={{
                fontFamily: F.display,
                fontWeight: 800,
                fontSize: fmt === "phone" ? 76 : 64,
                letterSpacing: -1.5,
                padding: "6px 22px",
                borderRadius: 18,
                color: i <= active ? C.ink : "rgba(255,255,255,0.35)",
                background: on ? C.blue : "transparent",
                boxShadow: on ? "0 0 50px rgba(6,115,236,0.8)" : "none",
                transform: `scale(${on ? 1 + 0.06 * (1 - Math.min(1, Math.abs(pop(f, 28 + i * 10, 10, 240) - 1) * 3)) : 1})`,
              }}
            >
              {s}
            </span>
          );
        })}
      </div>
      <Tagline f={f} start={54} text="TEMPLATES · DEVICE FRAMES · 80+ LANGUAGES" top={height * (fmt === "phone" ? 0.78 : 0.8)} size={fmt === "phone" ? 28 : 30} />
    </AbsoluteFill>
  );
};
