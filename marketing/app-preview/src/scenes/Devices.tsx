import React from "react";
import { AbsoluteFill } from "remotion";
import { AppWindow, Field, Section } from "../components/AppWindow";
import { Device, FrameKind, frameAspect } from "../components/Device";
import { ease, Header, INOUT, mix, pop, Pointer, useFmt, useLayout, useSceneFrame, Way } from "../components/kit";
import { BGS, gradient } from "../components/Row";
import { useArea } from "../components/AppWindow";
import { C, F } from "../theme";

type Step = { at: number; kind: FrameKind; item: number; color: string; ratio: number; d3?: boolean };

const ITEMS = ["iPhone 17 Pro", "iPhone Air", "iPhone 17", "iPad Pro 13″", "MacBook Air 13″", "iPhone 17 Pro (3D)"];
const PHONE = 1290 / 2796;
const SEQ: Step[] = [
  { at: -99, kind: "iphone17pro-deepblue", item: 0, color: "Deep Blue", ratio: PHONE },
  { at: 20, kind: "iphone17pro-orange", item: 0, color: "Cosmic Orange", ratio: PHONE },
  { at: 38, kind: "iphoneair-white", item: 1, color: "Cloud White", ratio: PHONE },
  { at: 54, kind: "iphone17-lavender", item: 2, color: "Lavender", ratio: PHONE },
  { at: 70, kind: "ipadpro13-gray", item: 3, color: "Space Gray", ratio: 2064 / 2752 },
  { at: 88, kind: "macbookair13-midnight", item: 4, color: "Midnight", ratio: 2880 / 1800 },
  { at: 106, kind: "iphone17pro-deepblue", item: 5, color: "Deep Blue", ratio: PHONE, d3: true },
];
const SWATCH: Record<string, string> = { "Deep Blue": "#2B3A5C", "Cosmic Orange": "#E8742A", "Cloud White": "#EDEDEA", Lavender: "#C9B8E8", "Space Gray": "#4A4B50", Midnight: "#2A2F3A" };

export const Devices: React.FC = () => {
  const f = useSceneFrame();
  const fmt = useFmt();
  const L = useLayout();
  const area = useArea();
  const phone = fmt === "phone";
  const idx = SEQ.reduce((m, s, i) => (f >= s.at ? i : m), 0);
  const cur = SEQ[idx];
  const prev = SEQ[Math.max(0, idx - 1)];
  const flip = idx > 0 ? Math.abs(Math.cos(ease(f, [cur.at - 1, cur.at + 7], [Math.PI / 2, Math.PI], INOUT))) : 1;
  const ratio = mix(prev.ratio, cur.ratio, idx > 0 ? ease(f, [cur.at - 4, cur.at + 8], [0, 1], INOUT) : 1);

  const maxW = area.w - (phone ? 90 : 120);
  const maxH = area.h - (phone ? 90 : 80);
  const bh = Math.min(maxH, maxW / ratio);
  const bw = bh * ratio;
  const bx = (area.w - bw) / 2;
  const by = (area.h - bh) / 2;
  const fr = frameAspect(cur.kind);
  const isPhone = cur.kind.startsWith("iphone");
  const dw = isPhone ? bw * 0.78 : Math.min(bw * 0.8, (bh * 0.64) / fr);
  const dTop = isPhone ? bh * 0.27 : bh * 0.3 + (bh * 0.66 - dw * fr) / 2;
  const tsize = Math.min(bw * 0.105, bh * 0.07);
  const d3 = cur.d3 ? ease(f, [cur.at, cur.at + 14], [0, 1], INOUT) : 0;
  const spin = d3 * (-26 + 10 * Math.sin((f - cur.at) / 7));

  const cx0 = L.panel.x;
  const cy0 = L.panel.y + L.toolbar;
  const ix0 = L.panel.x + L.panel.w - L.inspector;
  const itemY = (i: number) => cy0 + 64 + i * 52 + 22;
  const swatchX = (i: number) => ix0 + 22 + i * 46 + 16;
  const colorsY = cy0 + 64 + ITEMS.length * 52 + 58;
  const chipW = 300;
  const barY = L.panel.y + L.panel.h - L.bottom / 2;
  const path: Way[] = phone
    ? [{ at: 0, x: cx0 + area.w * 0.75, y: cy0 + area.h * 0.8 }, ...SEQ.slice(1).flatMap((s) => [{ at: s.at - 5, x: cx0 + L.panel.w / 2, y: barY }, { at: s.at - 1, x: cx0 + L.panel.w / 2, y: barY, click: true }])]
    : [
        { at: 0, x: cx0 + area.w * 0.8, y: cy0 + area.h * 0.8 },
        ...SEQ.slice(1).flatMap((s, i) => {
          const colorOnly = SEQ[i].item === s.item;
          const p = colorOnly ? { x: swatchX(1), y: colorsY } : { x: ix0 + L.inspector * 0.4, y: itemY(s.item) };
          return [{ at: s.at - 6, ...p }, { at: s.at - 1, ...p, click: true }];
        }),
      ];

  const inspector = (
    <>
      <Section title="Device frame">
        {ITEMS.map((it, i) => (
          <div key={it} style={{ height: 44, marginBottom: 8, display: "flex", alignItems: "center", padding: "0 14px", borderRadius: 10, background: i === cur.item ? "rgba(6,115,236,0.35)" : "transparent", border: i === cur.item ? `1.5px solid ${C.sky}` : "1.5px solid transparent", fontWeight: i === cur.item ? 700 : 500, color: i === cur.item ? C.ink : C.dim }}>
            {it}
          </div>
        ))}
      </Section>
      <Section title={`Color · ${cur.color}`}>
        <div style={{ display: "flex", gap: 14 }}>
          {(cur.item === 0 ? ["Deep Blue", "Cosmic Orange", "Silver"] : [cur.color]).map((c) => (
            <div key={c} style={{ width: 32, height: 32, borderRadius: 16, background: SWATCH[c] ?? "#C8C8CC", boxShadow: c === cur.color ? `0 0 0 3px ${C.win}, 0 0 0 5px ${C.sky}` : "none" }} />
          ))}
        </div>
      </Section>
      <Section title="Appearance">
        <Field label="Shadow" value="Soft" />
        <Field label="3D model" value={cur.d3 ? "On" : "Off"} hot={!!cur.d3} />
      </Section>
    </>
  );

  const chips = (
    <div style={{ position: "relative", height: "100%", overflow: "hidden" }}>
      <div style={{ position: "absolute", top: 50, left: L.panel.w / 2 - chipW / 2, display: "flex", gap: 16, transform: `translateX(${-cur.item * (chipW + 16)}px)` }}>
        {ITEMS.map((it, i) => (
          <div key={it} style={{ width: chipW, height: 90, flexShrink: 0, borderRadius: 26, display: "flex", alignItems: "center", justifyContent: "center", fontSize: 28, fontWeight: 700, background: i === cur.item ? C.blue : "rgba(255,255,255,0.08)", color: i === cur.item ? C.ink : C.dim }}>
            {it}
          </div>
        ))}
      </div>
    </div>
  );

  return (
    <AbsoluteFill>
      <Header num="03" title="Real device frames" sub="iPhone, iPad and Mac — or go 3D." />
      <div style={{ transform: `scale(${0.92 + 0.08 * pop(f, 0, 14, 140)})`, transformOrigin: `${L.panel.x + L.panel.w / 2}px ${L.panel.y + L.panel.h / 2}px`, position: "absolute", inset: 0 }}>
        <AppWindow inspector={inspector} bottom={chips} zoom="48%">
          <div style={{ position: "absolute", left: bx, top: by, width: bw, height: bh, overflow: "hidden", background: gradient(BGS.brand), boxShadow: "0 30px 80px rgba(0,0,0,0.45)" }}>
            <div style={{ position: "absolute", left: bw * 0.55, top: -bh * 0.1, width: bw * 0.8, height: bw * 0.8, borderRadius: "50%", background: "rgba(255,255,255,0.1)" }} />
            <div style={{ position: "absolute", top: bh * 0.07, left: 0, right: 0, textAlign: "center", fontFamily: F.display, fontWeight: 800, fontSize: tsize, lineHeight: 1.05, color: "#fff", whiteSpace: "pre-line" }}>
              {ratio > 1 ? "Build habits that stick" : "Build habits\nthat stick"}
            </div>
            {d3 > 0 && <div style={{ position: "absolute", left: bw / 2 - dw * 0.45, top: bh * 0.94, width: dw * 0.9, height: dw * 0.12, borderRadius: "50%", background: "rgba(0,0,0,0.35)", filter: "blur(18px)", opacity: d3 }} />}
            <div style={{ position: "absolute", left: (bw - dw) / 2, top: dTop, perspective: 1600 }}>
              <div style={{ transform: `scaleX(${flip}) rotateY(${spin}deg) rotateX(${d3 * 8}deg) scale(${1 - d3 * 0.12})`, transformOrigin: "50% 40%", filter: `drop-shadow(${-spin * 1.2}px 24px 30px rgba(0,0,0,${0.35 + d3 * 0.2}))` }}>
                <Device kind={cur.kind} width={dw} screen="today" />
              </div>
            </div>
            {d3 > 0 && (
              <div style={{ position: "absolute", right: bw * 0.06, top: bh * 0.3, padding: `${tsize * 0.15}px ${tsize * 0.4}px`, borderRadius: 999, background: "#fff", color: C.blue, fontFamily: F.display, fontWeight: 800, fontSize: tsize * 0.55, transform: `scale(${pop(f, cur.at + 6)})` }}>3D</div>
            )}
          </div>
          <div style={{ position: "absolute", left: bx, top: by + bh + 10, width: bw, textAlign: "center", fontSize: phone ? 24 : 15, color: C.dim, fontFamily: F.ui }}>
            {ITEMS[cur.item]} · {Math.round(ratio > 1 ? 2880 : ratio > 0.6 ? 2064 : 1290)} × {Math.round(ratio > 1 ? 1800 : ratio > 0.6 ? 2752 : 2796)}
          </div>
        </AppWindow>
        <Pointer f={f} path={path} />
      </div>
    </AbsoluteFill>
  );
};
