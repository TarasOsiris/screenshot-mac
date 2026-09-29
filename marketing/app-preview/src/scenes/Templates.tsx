import React from "react";
import { AbsoluteFill } from "remotion";
import { Sheet } from "../components/AppWindow";
import { ease, Header, INOUT, pop, Pointer, useFmt, useLayout, useSceneFrame } from "../components/kit";
import { Preview, PREVIEW_RATIO } from "../components/TemplateWall";
import { TEMPLATE_NAMES } from "../templates.gen";
import { C } from "../theme";

const CHIPS = ["All", "Colorful", "Dark", "Minimal", "Bold", "Editorial", "Gradient"];
const PICK = "royal-blue";

const title = (n: string) => n.replace(/-/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());

export const Templates: React.FC = () => {
  const f = useSceneFrame();
  const fmt = useFmt();
  const { panel, toolbar } = useLayout();
  const W = panel.w;
  const H = panel.h - toolbar;
  const cols = fmt === "phone" ? 2 : fmt === "pad" ? 4 : 5;
  const pad = fmt === "phone" ? 28 : 26;
  const gap = fmt === "phone" ? 24 : 20;
  const fs = fmt === "phone" ? 26 : fmt === "pad" ? 19 : 16;
  const chipsH = fmt === "phone" ? 100 : 70;
  const footH = fmt === "phone" ? 120 : 76;
  const cw = (W - 2 * pad - (cols - 1) * gap) / cols;
  const ph = cw / PREVIEW_RATIO;
  const ch = ph + fs * 2.2;
  const pickRow = fmt === "phone" ? 4 : 3;
  const pickCol = 1;
  const scrollEnd = (pickRow - (fmt === "phone" ? 1.6 : 1.2)) * (ch + gap);
  const scroll = ease(f, [4, 56], [0, scrollEnd], INOUT);
  const names = TEMPLATE_NAMES.filter((n) => n !== PICK);
  names.splice(pickRow * cols + pickCol, 0, PICK);
  const px = pad + pickCol * (cw + gap);
  const py = chipsH + pad + pickRow * (ch + gap) - scrollEnd;
  const picked = f >= 62;
  const zoom = ease(f, [96, 118], [0, 1], INOUT);
  const btnX = W - pad - (fmt === "phone" ? 150 : 90);
  const btnY = H - footH / 2;
  return (
    <AbsoluteFill>
      <Header num="01" title="Start from 60+ templates" sub="Pick a look, make it yours." />
      <div style={{ transform: `scale(${0.9 + 0.1 * pop(f, 0, 14, 140)})`, transformOrigin: `${panel.x + panel.w / 2}px ${panel.y + panel.h / 2}px`, position: "absolute", inset: 0 }}>
        <Sheet title="New Project">
          <div style={{ position: "absolute", left: 0, right: 0, top: chipsH, bottom: footH, overflow: "hidden" }}>
            <div style={{ position: "absolute", left: pad, top: pad - scroll, display: "grid", gridTemplateColumns: `repeat(${cols}, ${cw}px)`, gap }}>
              {names.slice(0, cols * 8).map((n, i) => {
                const on = n === PICK && picked;
                const k = pop(f, 2 + (i % cols) * 2 + Math.floor(i / cols) * 2, 13, 170);
                return (
                  <div key={n} style={{ width: cw, height: ch, opacity: Math.min(1, k * 1.4), transform: `translateY(${(1 - k) * 40}px)` }}>
                    <div style={{ borderRadius: ph * 0.07, padding: 3, background: on ? C.blue : "transparent", boxShadow: on ? "0 0 36px rgba(6,115,236,0.9)" : "0 8px 20px rgba(0,0,0,0.35)" }}>
                      <Preview name={n} h={ph - 6} style={{ width: cw - 6, display: "block" }} />
                    </div>
                    <div style={{ fontSize: fs, fontWeight: 600, marginTop: fs * 0.5, color: on ? C.sky : C.dim, textAlign: "center" }}>{title(n)}</div>
                  </div>
                );
              })}
            </div>
            {zoom > 0 && (
              <div
                style={{
                  position: "absolute",
                  left: px,
                  top: py - chipsH,
                  width: cw,
                  height: ph,
                  transform: `translate(${(W / 2 - px - cw / 2) * zoom}px, ${((H - chipsH - footH) / 2 - (py - chipsH) - ph / 2) * zoom}px) scale(${1 + zoom * (fmt === "phone" ? 1.2 : 1.8)})`,
                  boxShadow: `0 0 ${80 * zoom}px rgba(6,115,236,0.8)`,
                  borderRadius: ph * 0.07,
                  overflow: "hidden",
                }}
              >
                <Preview name={PICK} h={ph} style={{ width: cw, borderRadius: 0, display: "block" }} />
              </div>
            )}
          </div>
          <div style={{ position: "absolute", left: 0, right: 0, top: 0, height: chipsH, display: "flex", alignItems: "center", gap: 10, padding: `0 ${pad}px`, borderBottom: `1px solid ${C.line}` }}>
            {CHIPS.slice(0, fmt === "phone" ? 4 : CHIPS.length).map((c, i) => (
              <div key={c} style={{ padding: `${fs * 0.35}px ${fs * 0.9}px`, borderRadius: 999, fontSize: fs, fontWeight: 600, background: i === 0 ? C.blue : "rgba(255,255,255,0.08)", color: i === 0 ? C.ink : C.dim }}>
                {c}
              </div>
            ))}
          </div>
          <div style={{ position: "absolute", left: 0, right: 0, bottom: 0, height: footH, display: "flex", alignItems: "center", justifyContent: "space-between", padding: `0 ${pad}px`, background: C.bar, borderTop: `1px solid ${C.line}` }}>
            <div style={{ fontSize: fs, color: C.dim }}>63 templates</div>
            <div style={{ display: "flex", gap: 12, fontSize: fs, fontWeight: 600 }}>
              <div style={{ padding: `${fs * 0.45}px ${fs}px`, borderRadius: 10, background: "rgba(255,255,255,0.08)" }}>Cancel</div>
              <div style={{ padding: `${fs * 0.45}px ${fs}px`, borderRadius: 10, background: C.blue, opacity: picked ? 1 : 0.45, transform: `scale(${f > 94 && f < 104 ? 0.94 : 1})` }}>Create Project</div>
            </div>
          </div>
          <Pointer
            f={f}
            path={[
              { at: 0, x: W * 0.8, y: H * 0.9 },
              { at: 50, x: px + cw * 0.55, y: py + ph * 0.5 },
              { at: 62, x: px + cw * 0.55, y: py + ph * 0.5, click: true },
              { at: 86, x: btnX, y: btnY },
              { at: 96, x: btnX, y: btnY, click: true },
            ]}
          />
        </Sheet>
      </div>
    </AbsoluteFill>
  );
};
