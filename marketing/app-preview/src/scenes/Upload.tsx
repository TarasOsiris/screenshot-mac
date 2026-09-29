import React from "react";
import { AbsoluteFill, random } from "remotion";
import { Sheet } from "../components/AppWindow";
import { ease, Header, INOUT, pop, Pointer, useFmt, useLayout, useSceneFrame } from "../components/kit";
import { C, F } from "../theme";

const LOCALES = [
  ["🇺🇸", "English (U.S.)"],
  ["🇩🇪", "German"],
  ["🇫🇷", "French"],
  ["🇯🇵", "Japanese"],
  ["🇪🇸", "Spanish (Spain)"],
  ["🇺🇦", "Ukrainian"],
  ["🇧🇷", "Portuguese (Brazil)"],
  ["🇰🇷", "Korean"],
];
const DEST = [
  { icon: "▤", name: "Folder", sub: "PNG or JPEG, every size" },
  { icon: "⇪", name: "App Store Connect", sub: "Upload straight to your app" },
  { icon: "▦", name: "Showcase", sub: "One marketing image" },
];
const PICK_AT = 24;
const LIST_AT = 38;
const DONE_AT = 128;
const TOTAL = LOCALES.length * 8;

const AppIcon: React.FC<{ size: number }> = ({ size }) => (
  <div style={{ width: size, height: size, borderRadius: size * 0.23, background: "linear-gradient(135deg,#4DB5FF,#0673EC 55%,#3A1D8F)", display: "flex", alignItems: "center", justifyContent: "center", boxShadow: "0 6px 20px rgba(6,115,236,0.5)" }}>
    <svg width={size * 0.6} height={size * 0.6} viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="3" strokeLinecap="round">
      <circle cx="12" cy="12" r="8.5" strokeOpacity="0.35" />
      <path d="M12 3.5 A8.5 8.5 0 0 1 20.5 12" />
      <path d="M8.5 12.2 L11 14.6 L15.8 9.6" />
    </svg>
  </div>
);

export const Upload: React.FC = () => {
  const f = useSceneFrame();
  const fmt = useFmt();
  const L = useLayout();
  const phone = fmt === "phone";
  const W = L.panel.w;
  const H = L.panel.h - L.toolbar;
  const s = phone ? 1.5 : fmt === "pad" ? 1.12 : 1;
  const pad = 30 * s;

  // Phase A: choose the destination.
  const cardsOut = ease(f, [LIST_AT - 8, LIST_AT], [0, 1], INOUT);
  const cw = phone ? W - 2 * pad : (W - 2 * pad - 2 * 24) / 3;
  const chh = phone ? 230 : 220 * s;
  const cardPos = (i: number) => (phone ? { x: pad, y: 120 + i * (chh + 28) } : { x: pad + i * (cw + 24), y: (H - chh) / 2 });

  // Phase B: per-locale upload rows.
  const rowH = phone ? 106 : 68 * s;
  const listTop = phone ? 270 : 120 * s;
  const prog = (i: number) => ease(f, [LIST_AT + 6 + i * 9, LIST_AT + 32 + i * 9], [0, 1], (t) => t);
  const uploaded = Math.round(LOCALES.reduce((a, _, i) => a + prog(i) * 8, 0));
  const done = f >= DONE_AT;
  const burst = ease(f, [DONE_AT, DONE_AT + 24], [0, 1]);
  const p1 = cardPos(1);

  return (
    <AbsoluteFill>
      <Header num="05" title="Upload to App Store Connect" sub="Every size, every language — in one go." />
      <div style={{ transform: `scale(${0.92 + 0.08 * pop(f, 0, 14, 140)})`, transformOrigin: `${L.panel.x + L.panel.w / 2}px ${L.panel.y + L.panel.h / 2}px`, position: "absolute", inset: 0 }}>
        <Sheet title={f < LIST_AT ? "Export" : "Upload to App Store Connect"}>
          {cardsOut < 1 && (
            <div style={{ position: "absolute", inset: 0, opacity: 1 - cardsOut, transform: `scale(${1 - cardsOut * 0.08})` }}>
              {!phone && <div style={{ position: "absolute", left: 0, right: 0, top: H / 2 - chh / 2 - 70 * s, textAlign: "center", fontSize: 20 * s, color: C.dim }}>Where should the screenshots go?</div>}
              {DEST.map((d, i) => {
                const p = cardPos(i);
                const on = i === 1 && f >= PICK_AT;
                return (
                  <div key={d.name} style={{ position: "absolute", left: p.x, top: p.y, width: cw, height: chh, borderRadius: 22, background: on ? "rgba(6,115,236,0.3)" : "rgba(255,255,255,0.05)", border: `2px solid ${on ? C.sky : C.line}`, boxShadow: on ? "0 0 40px rgba(6,115,236,0.6)" : "none", display: "flex", flexDirection: phone ? "row" : "column", alignItems: "center", justifyContent: "center", gap: 18 * s, padding: 20, transform: `scale(${pop(f, 2 + i * 3) * (on ? 1.03 : 1)})` }}>
                    <div style={{ width: 70 * s, height: 70 * s, borderRadius: 18 * s, background: i === 1 ? C.blue : "rgba(255,255,255,0.1)", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 36 * s, color: "#fff" }}>{d.icon}</div>
                    <div style={{ textAlign: phone ? "left" : "center" }}>
                      <div style={{ fontSize: 22 * s, fontWeight: 700 }}>{d.name}</div>
                      <div style={{ fontSize: 16 * s, color: C.dim, marginTop: 6 }}>{d.sub}</div>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
          {f >= LIST_AT - 2 && (
            <div style={{ position: "absolute", inset: 0, opacity: ease(f, [LIST_AT - 2, LIST_AT + 6], [0, 1]) }}>
              <div style={{ position: "absolute", left: pad, right: pad, top: 26 * s, display: "flex", alignItems: "center", gap: 18 * s, flexWrap: phone ? "wrap" : "nowrap" }}>
                <AppIcon size={64 * s} />
                <div style={{ flex: 1 }}>
                  <div style={{ fontSize: 24 * s, fontWeight: 700 }}>Habitly</div>
                  <div style={{ fontSize: 16 * s, color: C.dim, marginTop: 4 }}>iOS · Version 2.4 · Prepare for Submission</div>
                </div>
                <div style={{ textAlign: "right", fontVariantNumeric: "tabular-nums", width: phone ? "100%" : "auto", marginTop: phone ? 10 : 0 }}>
                  <span style={{ fontFamily: F.display, fontWeight: 800, fontSize: 40 * s, color: done ? C.green : C.ink }}>{uploaded}</span>
                  <span style={{ fontSize: 20 * s, color: C.dim }}> / {TOTAL} screenshots</span>
                </div>
              </div>
              {LOCALES.map(([flag, name], i) => {
                const p = prog(i);
                const y = listTop + i * rowH;
                return (
                  <div key={name} style={{ position: "absolute", left: pad, right: pad, top: y, height: rowH - 10, display: "flex", alignItems: "center", gap: 16 * s, padding: `0 ${16 * s}px`, borderRadius: 14, background: "rgba(255,255,255,0.04)", opacity: ease(f, [LIST_AT + i * 2, LIST_AT + i * 2 + 6], [0, 1]) }}>
                    <span style={{ fontSize: 26 * s }}>{flag}</span>
                    <span style={{ width: phone ? 250 : 220 * s, fontSize: 18 * s, fontWeight: 600, whiteSpace: "nowrap" }}>{name}</span>
                    {!phone &&
                      ["iPhone 6.9″", "iPad 13″"].map((d, j) => (
                        <span key={d} style={{ fontSize: 14 * s, padding: `${4 * s}px ${10 * s}px`, borderRadius: 999, background: "rgba(255,255,255,0.07)", color: C.dim, whiteSpace: "nowrap" }}>
                          {d} · {Math.max(0, Math.min(4, Math.floor(p * 8 - j * 4)))}/4
                        </span>
                      ))}
                    <div style={{ flex: 1, height: 10 * s, borderRadius: 5 * s, background: "rgba(255,255,255,0.08)", overflow: "hidden" }}>
                      <div style={{ width: `${p * 100}%`, height: "100%", borderRadius: 5 * s, background: p >= 1 ? C.green : `linear-gradient(90deg, ${C.blue}, ${C.sky})` }} />
                    </div>
                    <div style={{ width: 30 * s, height: 30 * s, borderRadius: 15 * s, background: p >= 1 ? C.green : "transparent", border: p >= 1 ? "none" : `2px solid ${C.line}`, display: "flex", alignItems: "center", justifyContent: "center", fontSize: 17 * s, fontWeight: 800, color: "#062", transform: `scale(${p >= 1 ? pop(f, LIST_AT + 32 + i * 9, 9, 260) : 1})` }}>
                      {p >= 1 ? "✓" : ""}
                    </div>
                  </div>
                );
              })}
              {done && (
                <div style={{ position: "absolute", left: 0, right: 0, bottom: phone ? 36 : 26 * s, display: "flex", justifyContent: "center" }}>
                  <div style={{ padding: `${14 * s}px ${30 * s}px`, borderRadius: 999, background: C.green, color: "#032", fontSize: 22 * s, fontWeight: 800, transform: `scale(${pop(f, DONE_AT, 9, 200)})`, boxShadow: "0 0 50px rgba(46,230,168,0.6)" }}>
                    ✓ Uploaded — ready for review
                  </div>
                </div>
              )}
              {done &&
                Array.from({ length: 28 }).map((_, i) => {
                  const a = (i / 28) * Math.PI * 2 + random(`ua${i}`) * 0.3;
                  const d = (160 + random(`ud${i}`) * 320) * burst * s;
                  return <div key={i} style={{ position: "absolute", left: W / 2 + Math.cos(a) * d * 1.6, top: H - 60 * s + Math.sin(a) * d * 0.7, width: 12, height: 12, borderRadius: 6, background: i % 3 ? C.sky : C.green, opacity: 1 - burst }} />;
                })}
            </div>
          )}
          <Pointer
            f={f}
            path={[
              { at: 0, x: W * 0.85, y: H * 0.85 },
              { at: PICK_AT - 2, x: p1.x + cw * 0.5, y: p1.y + chh * 0.55 },
              { at: PICK_AT, x: p1.x + cw * 0.5, y: p1.y + chh * 0.55, click: true },
              { at: PICK_AT + 30, x: W * 0.9, y: H * 0.55 },
            ]}
          />
        </Sheet>
      </div>
    </AbsoluteFill>
  );
};
