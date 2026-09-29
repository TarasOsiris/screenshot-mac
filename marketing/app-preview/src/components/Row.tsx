import React from "react";
import { F } from "../theme";
import { Device, FrameKind, frameAspect, ScreenKind } from "./Device";

// 6.9" App Store screenshot, 1290x2796 — the template aspect the editor shows.
export const TEMPLATE_RATIO = 1290 / 2796;

export type Slot = { title: string; screen: ScreenKind };

export const SLOTS: Slot[] = [
  { title: "Build habits\nthat stick", screen: "today" },
  { title: "See your\nprogress", screen: "stats" },
  { title: "Stay in\nthe zone", screen: "focus" },
  { title: "Never miss\na day", screen: "calendar" },
];

export type Bg = { stops: string[]; angle: number };

export const BGS: Record<string, Bg> = {
  brand: { stops: ["#0A1F6B", "#0673EC", "#4DB5FF"], angle: 120 },
  sunset: { stops: ["#5B1A8C", "#FF4F8B", "#FFB23F"], angle: 120 },
  mint: { stops: ["#053B3A", "#0E8C7A", "#2EE6A8"], angle: 120 },
};

export const gradient = (bg: Bg) => `linear-gradient(${bg.angle}deg, ${bg.stops.map((c, i) => `${c} ${(i / (bg.stops.length - 1)) * 100}%`).join(", ")})`;

export type Tweak = { dx?: number; dy?: number; rot?: number; scale?: number; title?: string; titleStyle?: React.CSSProperties; frame?: FrameKind };

export const Row: React.FC<{
  h: number;
  slots?: Slot[];
  bg: Bg;
  bgB?: Bg;
  bgMix?: number;
  frame?: FrameKind;
  tweak?: (i: number) => Tweak;
  separators?: boolean;
  radius?: number;
  font?: string;
  children?: React.ReactNode;
}> = ({ h, slots = SLOTS, bg, bgB, bgMix = 0, frame = "iphone17pro-deepblue", tweak, separators = true, radius = 0, font = F.display, children }) => {
  const w = h * TEMPLATE_RATIO;
  const total = w * slots.length;
  return (
    <div style={{ position: "relative", width: total, height: h, borderRadius: radius, overflow: "hidden", boxShadow: "0 30px 80px rgba(0,0,0,0.45)" }}>
      {/* One background spans the whole row, like the editor's spanning gradient. */}
      <div style={{ position: "absolute", inset: 0, background: gradient(bg) }} />
      {bgB && <div style={{ position: "absolute", inset: 0, background: gradient(bgB), opacity: bgMix }} />}
      {/* Shapes live on the shared canvas, so they cross template boundaries. */}
      <div style={{ position: "absolute", left: w * 0.62, top: -h * 0.12, width: w * 0.9, height: w * 0.9, borderRadius: "50%", background: "rgba(255,255,255,0.10)" }} />
      <div style={{ position: "absolute", left: w * 2.55, top: h * 0.62, width: w * 1.1, height: w * 1.1, borderRadius: "50%", background: "rgba(255,255,255,0.08)" }} />
      <div style={{ position: "absolute", left: -w * 0.2, top: h * 0.7, width: w * 0.7, height: w * 0.7, borderRadius: "50%", background: "rgba(255,255,255,0.07)" }} />
      {slots.map((s, i) => {
        const t = tweak?.(i) ?? {};
        const fk = t.frame ?? frame;
        const dw = w * 0.8 * (fk.startsWith("ipad") ? 1.08 : 1);
        return (
          <div key={i} style={{ position: "absolute", left: i * w, top: 0, width: w, height: h, overflow: "hidden" }}>
            <div
              style={{
                position: "absolute",
                top: h * 0.065,
                left: w * 0.06,
                right: w * 0.06,
                textAlign: "center",
                whiteSpace: "pre-line",
                fontFamily: font,
                fontWeight: 800,
                fontSize: w * 0.108,
                lineHeight: 1.05,
                letterSpacing: -w * 0.003,
                color: "#fff",
                ...t.titleStyle,
              }}
            >
              {t.title ?? s.title}
            </div>
            <div
              style={{
                position: "absolute",
                left: (w - dw) / 2 + (t.dx ?? 0),
                top: h * 0.27 + (t.dy ?? 0),
                transform: `rotate(${t.rot ?? 0}deg) scale(${t.scale ?? 1})`,
                transformOrigin: "50% 30%",
                filter: "drop-shadow(0 18px 30px rgba(0,0,0,0.35))",
              }}
            >
              <Device kind={fk} width={dw} screen={s.screen} />
            </div>
          </div>
        );
      })}
      {separators &&
        slots.slice(1).map((_, i) => (
          <div key={i} style={{ position: "absolute", left: (i + 1) * w - 1, top: 0, bottom: 0, width: 2, background: "rgba(255,255,255,0.35)" }} />
        ))}
      {children}
    </div>
  );
};

// Geometry of a slot's device in row coordinates, for drawing selections over it.
export const deviceBox = (h: number, i: number, t: Tweak = {}, frame: FrameKind = "iphone17pro-deepblue") => {
  const w = h * TEMPLATE_RATIO;
  const dw = w * 0.8;
  return { x: i * w + (w - dw) / 2 + (t.dx ?? 0), y: h * 0.27 + (t.dy ?? 0), w: dw, h: dw * frameAspect(frame) };
};
