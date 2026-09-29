import React from "react";
import { AbsoluteFill, Easing, interpolate, random, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { C, F, FPS, T } from "../theme";

export const OUT = Easing.bezier(0.16, 1, 0.3, 1);
export const INOUT = Easing.bezier(0.65, 0, 0.35, 1);

export const ease = (f: number, [a, b]: [number, number], [x, y]: [number, number], easing = OUT) =>
  interpolate(f, [a, b], [x, y], { easing, extrapolateLeft: "clamp", extrapolateRight: "clamp" });

export const pop = (f: number, start: number, damping = 12, stiffness = 180) =>
  spring({ frame: f - start, fps: FPS, config: { damping, stiffness, mass: 0.6 } });

export const mix = (a: number, b: number, t: number) => a + (b - a) * t;

// Scene-local frame: 0 at the cut the scene enters on (its Sequence starts T early).
export const useSceneFrame = () => useCurrentFrame() - T;

export type Fmt = "phone" | "pad" | "desk";

export const useFmt = (): Fmt => {
  const { width, height } = useVideoConfig();
  const r = width / height;
  return r < 1 ? "phone" : r > 1.5 ? "desk" : "pad";
};

type Rect = { x: number; y: number; w: number; h: number };
export type Layout = { header: { x: number; y: number; size: number; sub: number; maxW: number }; panel: Rect; toolbar: number; inspector: number; bottom: number };

// Where the headline and the app window sit in each composition.
export const LAYOUTS: Record<Fmt, Layout> = {
  phone: { header: { x: 56, y: 110, size: 84, sub: 36, maxW: 780 }, panel: { x: 36, y: 470, w: 814, h: 1390 }, toolbar: 96, inspector: 0, bottom: 190 },
  pad: { header: { x: 72, y: 60, size: 88, sub: 32, maxW: 1460 }, panel: { x: 60, y: 250, w: 1480, h: 900 }, toolbar: 64, inspector: 340, bottom: 0 },
  desk: { header: { x: 80, y: 40, size: 84, sub: 30, maxW: 1760 }, panel: { x: 70, y: 196, w: 1780, h: 852 }, toolbar: 56, inspector: 380, bottom: 0 },
};

export const useLayout = () => LAYOUTS[useFmt()];

export const Backdrop: React.FC = () => {
  const f = useCurrentFrame();
  const { width, height } = useVideoConfig();
  const gx = 50 + Math.sin(f / 70) * 20;
  const gy = 40 + Math.cos(f / 90) * 12;
  const step = 56;
  return (
    <AbsoluteFill style={{ background: C.bg, overflow: "hidden" }}>
      <AbsoluteFill
        style={{
          background: `radial-gradient(60% 40% at ${gx}% ${gy}%, rgba(6,115,236,0.45), transparent 70%),
            radial-gradient(45% 30% at ${100 - gx}% ${gy + 45}%, rgba(123,97,255,0.25), transparent 70%)`,
        }}
      />
      <AbsoluteFill
        style={{
          backgroundImage: "radial-gradient(rgba(255,255,255,0.09) 1.5px, transparent 1.5px)",
          backgroundSize: `${step}px ${step}px`,
          backgroundPosition: `${(f * 0.4) % step}px ${(f * 0.8) % step}px`,
          maskImage: "radial-gradient(70% 60% at 50% 45%, #000, transparent)",
        }}
      />
      {Array.from({ length: 24 }).map((_, i) => {
        const x = random(`px${i}`) * width;
        const speed = 0.3 + random(`ps${i}`) * 1;
        const y = (((random(`py${i}`) * height - f * speed) % height) + height) % height;
        const s = 2 + random(`pz${i}`) * 3;
        return (
          <div
            key={i}
            style={{ position: "absolute", left: x, top: y, width: s, height: s, borderRadius: s, background: C.sky, opacity: 0.12 + random(`po${i}`) * 0.3, boxShadow: `0 0 ${s * 3}px ${C.sky}` }}
          />
        );
      })}
    </AbsoluteFill>
  );
};

type Move = "whip" | "zoom" | "fade" | "none";

// Renders a scene across its whole window, T frames either side of its cuts, and
// owns the transition in and out so no scene has to think about its neighbours.
export const SceneShell: React.FC<{ dur: number; enter?: Move; exit?: Move; children: React.ReactNode }> = ({ dur, enter = "whip", exit = "whip", children }) => {
  const raw = useCurrentFrame();
  const { width } = useVideoConfig();
  const pin = ease(raw, [0, 2 * T], [0, 1], INOUT);
  const pout = ease(raw, [dur, dur + 2 * T], [0, 1], INOUT);
  let x = 0;
  let scale = 1;
  let blur = 0;
  let opacity = 1;
  if (enter !== "none" && pin < 1) {
    if (enter === "whip") {
      x += (1 - pin) * width * 0.6;
      blur += (1 - pin) * 60;
      opacity *= Math.min(1, pin * 2);
    } else if (enter === "zoom") {
      scale *= 0.7 + 0.3 * pin;
      blur += (1 - pin) * 30;
      opacity *= pin;
    } else opacity *= pin;
  }
  if (exit !== "none" && pout > 0) {
    if (exit === "whip") {
      x -= pout * width * 0.6;
      blur += pout * 60;
      opacity *= Math.min(1, (1 - pout) * 2);
    } else if (exit === "zoom") {
      scale *= 1 + pout * 5;
      blur += pout * 24;
      opacity *= 1 - pout;
    } else opacity *= 1 - pout;
  }
  const id = `whip-${Math.round(blur)}`;
  const zooming = enter === "zoom" || exit === "zoom";
  return (
    <AbsoluteFill style={{ opacity }}>
      {blur > 0.5 && (
        <svg width="0" height="0" style={{ position: "absolute" }}>
          <filter id={id} x="-20%" y="0" width="140%" height="100%">
            <feGaussianBlur stdDeviation={`${blur} 0`} />
          </filter>
        </svg>
      )}
      <AbsoluteFill style={{ transform: `translateX(${x}px) scale(${scale})`, filter: blur > 0.5 ? (zooming ? `blur(${blur / 3}px)` : `url(#${id})`) : undefined }}>
        {children}
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

export const CutFlash: React.FC<{ at: number }> = ({ at }) => {
  const f = useCurrentFrame();
  const p = interpolate(f, [at - 4, at, at + 6], [0, 1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  if (p <= 0) return null;
  return (
    <AbsoluteFill style={{ pointerEvents: "none", mixBlendMode: "screen" }}>
      {[0.3, 0.46, 0.52, 0.71].map((y, i) => (
        <div
          key={i}
          style={{
            position: "absolute",
            left: 0,
            right: 0,
            top: `${y * 100}%`,
            height: 4 + i * 6,
            background: `linear-gradient(90deg, transparent, ${i % 2 ? C.violet : C.sky}, transparent)`,
            opacity: p * 0.9,
            filter: "blur(2px)",
            transform: `translateX(${(1 - p) * (i % 2 ? 300 : -300)}px)`,
          }}
        />
      ))}
      <AbsoluteFill style={{ background: C.blue, opacity: p * 0.12 }} />
    </AbsoluteFill>
  );
};

// Scene headline: a numbered title whose words rise in one by one, plus a subline.
export const Header: React.FC<{ num: string; title: string; sub?: string; start?: number }> = ({ num, title, sub, start = 2 }) => {
  const f = useSceneFrame();
  const { header: h } = useLayout();
  const words = title.split(" ");
  return (
    <div style={{ position: "absolute", left: h.x, top: h.y, width: h.maxW }}>
      <div style={{ display: "flex", alignItems: "flex-start", gap: 18 }}>
        <div
          style={{
            fontFamily: F.display,
            fontWeight: 700,
            fontSize: h.sub,
            color: C.sky,
            marginTop: h.size * 0.14,
            opacity: ease(f, [start, start + 8], [0, 1]),
            transform: `translateY(${ease(f, [start, start + 10], [20, 0])}px)`,
          }}
        >
          {num}
        </div>
        <div style={{ display: "flex", flexWrap: "wrap", columnGap: h.size * 0.26, rowGap: 0 }}>
          {words.map((w, i) => {
            const s = start + 2 + i * 3;
            return (
              <div key={i} style={{ overflow: "hidden", paddingBottom: h.size * 0.08 }}>
                <div
                  style={{
                    fontFamily: F.display,
                    fontWeight: 800,
                    fontSize: h.size,
                    lineHeight: 1.02,
                    letterSpacing: -h.size * 0.035,
                    color: C.ink,
                    transform: `translateY(${ease(f, [s, s + 12], [110, 0])}%)`,
                  }}
                >
                  {w}
                </div>
              </div>
            );
          })}
        </div>
      </div>
      {sub && (
        <div
          style={{
            fontFamily: F.display,
            fontWeight: 500,
            fontSize: h.sub,
            color: C.dim,
            marginTop: 8,
            marginLeft: h.sub * 1.5 + 18,
            opacity: ease(f, [start + 10, start + 20], [0, 1]),
            transform: `translateY(${ease(f, [start + 10, start + 22], [16, 0])}px)`,
          }}
        >
          {sub}
        </div>
      )}
    </div>
  );
};

// A pointer that eases between waypoints. Desktop draws the macOS arrow; touch
// formats draw a finger dot that presses on each click.
export type Way = { at: number; x: number; y: number; click?: boolean };

export const Pointer: React.FC<{ f: number; path: Way[]; scale?: number }> = ({ f, path, scale = 1 }) => {
  const fmt = useFmt();
  let x = path[0].x;
  let y = path[0].y;
  for (let i = 1; i < path.length; i++) {
    const a = path[i - 1];
    const b = path[i];
    if (f >= a.at) {
      const p = ease(f, [a.at, b.at], [0, 1], INOUT);
      x = mix(a.x, b.x, p);
      y = mix(a.y, b.y, p);
    }
  }
  const press = path.reduce((m, w) => (w.click ? Math.max(m, interpolate(f, [w.at - 2, w.at + 1, w.at + 7], [0, 1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" })) : m), 0);
  const ripple = path.filter((w) => w.click && f >= w.at && f < w.at + 14).map((w) => (f - w.at) / 14);
  const s = scale * (fmt === "desk" ? 1 : 1.3);
  return (
    <div style={{ position: "absolute", left: x, top: y, width: 0, height: 0, zIndex: 50, pointerEvents: "none" }}>
      {ripple.map((r, i) => (
        <div key={i} style={{ position: "absolute", left: -40 * r * s, top: -40 * r * s, width: 80 * r * s, height: 80 * r * s, borderRadius: "50%", border: `3px solid rgba(255,255,255,${1 - r})` }} />
      ))}
      {fmt === "desk" ? (
        <svg width={30 * s} height={44 * s} viewBox="0 0 30 44" style={{ position: "absolute", left: -3 * s, top: -2 * s, transform: `scale(${1 - press * 0.12})`, filter: "drop-shadow(0 3px 5px rgba(0,0,0,0.5))" }}>
          <path d="M3 2 L3 33 L10.5 26 L15.5 38 L20.5 36 L15.5 24.5 L25.5 24.5 Z" fill="#000" stroke="#fff" strokeWidth="2.4" strokeLinejoin="round" />
        </svg>
      ) : (
        <div style={{ position: "absolute", left: -26 * s, top: -26 * s, width: 52 * s, height: 52 * s, borderRadius: "50%", background: "rgba(255,255,255,0.55)", border: "2px solid rgba(255,255,255,0.9)", boxShadow: "0 4px 18px rgba(0,0,0,0.35)", transform: `scale(${1 - press * 0.25})` }} />
      )}
    </div>
  );
};

// Sketch-style selection: blue hairline with white square handles.
export const Selection: React.FC<{ x: number; y: number; w: number; h: number; rot?: number; opacity?: number; handle?: number; origin?: string }> = ({ x, y, w, h, rot = 0, opacity = 1, handle = 12, origin = "50% 50%" }) => (
  <div style={{ position: "absolute", left: x, top: y, width: w, height: h, transform: `rotate(${rot}deg)`, transformOrigin: origin, opacity, border: `2px solid ${C.blue}`, pointerEvents: "none", zIndex: 20 }}>
    {[
      [0, 0],
      [0.5, 0],
      [1, 0],
      [0, 0.5],
      [1, 0.5],
      [0, 1],
      [0.5, 1],
      [1, 1],
    ].map(([a, b], i) => (
      <div key={i} style={{ position: "absolute", left: `calc(${a * 100}% - ${handle / 2 + 1}px)`, top: `calc(${b * 100}% - ${handle / 2 + 1}px)`, width: handle, height: handle, background: "#fff", border: `2px solid ${C.blue}`, borderRadius: 2 }} />
    ))}
  </div>
);
