import React from "react";
import { AbsoluteFill } from "remotion";
import { AppWindow, Section, useArea } from "../components/AppWindow";
import { ease, Header, INOUT, pop, Pointer, useFmt, useLayout, useSceneFrame, Way } from "../components/kit";
import { BGS, Row, SLOTS, TEMPLATE_RATIO } from "../components/Row";
import { C, F } from "../theme";

const LANGS = [
  { flag: "🇺🇸", name: "English", t: ["Build habits\nthat stick", "See your\nprogress", "Stay in\nthe zone"] },
  { flag: "🇩🇪", name: "Deutsch", t: ["Gewohnheiten,\ndie bleiben", "Sieh deinen\nFortschritt", "Bleib im\nFlow"] },
  { flag: "🇫🇷", name: "Français", t: ["Des habitudes\nqui durent", "Suivez vos\nprogrès", "Restez\nconcentré"] },
  { flag: "🇯🇵", name: "日本語", t: ["続く習慣を\nつくろう", "進歩を\n見える化", "集中を\n保とう"] },
  { flag: "🇪🇸", name: "Español", t: ["Hábitos que\nperduran", "Mira tu\nprogreso", "Mantén el\nenfoque"] },
  { flag: "🇺🇦", name: "Українська", t: ["Звички, що\nлишаються", "Бачте свій\nпрогрес", "Тримайте\nфокус"] },
  { flag: "🇧🇷", name: "Português", t: ["Hábitos que\nficam", "Veja seu\nprogresso", "Fique no\nfoco"] },
  { flag: "🇰🇷", name: "한국어", t: ["오래가는\n습관 만들기", "성장을\n한눈에", "몰입을\n유지하세요"] },
];
const SWITCH = [-99, 22, 40, 56, 72, 86, 100, 114];

const Flip: React.FC<{ f: number; slot: number; size: number }> = ({ f, slot, size }) => {
  const idx = SWITCH.reduce((m, s, i) => (f >= s + slot * 2 ? i : m), 0);
  const at = SWITCH[idx] + slot * 2;
  const p = idx > 0 ? ease(f, [at, at + 8], [0, 1], INOUT) : 1;
  const old = LANGS[Math.max(0, idx - 1)].t[slot];
  const cur = LANGS[idx].t[slot];
  const line: React.CSSProperties = { position: "absolute", inset: 0, whiteSpace: "pre-line", fontFamily: F.display, fontWeight: 800, fontSize: size, lineHeight: 1.08, textAlign: "center", color: "#fff" };
  return (
    <div style={{ position: "relative", height: size * 2.3, overflow: "hidden" }}>
      {p < 1 && <div style={{ ...line, transform: `translateY(${-p * 60}%)`, opacity: 1 - p, filter: `blur(${p * 6}px)` }}>{old}</div>}
      <div style={{ ...line, transform: `translateY(${(1 - p) * 60}%)`, opacity: p, filter: `blur(${(1 - p) * 6}px)` }}>{cur}</div>
    </div>
  );
};

export const Localize: React.FC = () => {
  const f = useSceneFrame();
  const fmt = useFmt();
  const L = useLayout();
  const area = useArea();
  const phone = fmt === "phone";
  const n = phone ? 2 : 3;
  const h = phone ? Math.min(area.h - 90, (area.w - 60) / (n * TEMPLATE_RATIO)) : Math.min(area.h - 60, (area.w - 80) / (n * TEMPLATE_RATIO));
  const w = h * TEMPLATE_RATIO;
  const rx = (area.w - n * w) / 2;
  const ry = (area.h - h) / 2;
  const idx = SWITCH.reduce((m, s, i) => (f >= s ? i : m), 0);
  const lang = LANGS[idx];
  const cx0 = L.panel.x;
  const cy0 = L.panel.y + L.toolbar;
  const ix0 = L.panel.x + L.panel.w - L.inspector;
  const rowY = (i: number) => cy0 + 64 + i * 50 + 20;
  const localeBtn = { x: L.panel.x + L.panel.w - (phone ? 200 : fmt === "pad" ? 250 : 230), y: L.panel.y + L.toolbar / 2 };
  const path: Way[] = phone
    ? [{ at: 0, x: cx0 + area.w * 0.6, y: cy0 + area.h * 0.8 }, ...SWITCH.slice(1).flatMap((s) => [{ at: s - 5, ...localeBtn }, { at: s - 1, ...localeBtn, click: true }])]
    : [{ at: 0, x: cx0 + area.w * 0.7, y: cy0 + area.h * 0.8 }, ...SWITCH.slice(1, fmt === "desk" ? 5 : 8).flatMap((s, i) => [{ at: s - 6, x: ix0 + 150, y: rowY(i + 1) }, { at: s - 1, x: ix0 + 150, y: rowY(i + 1), click: true }]), ...(fmt === "desk" ? [{ at: 80, x: ix0 + 200, y: rowY(7) + 90 }] : [])];
  const keycap = fmt === "desk" && f >= 78;
  const keyPress = SWITCH.slice(5).some((s) => f >= s - 2 && f < s + 4);

  const inspector = (
    <Section title={`Languages · ${LANGS.length} of 80+`}>
      {LANGS.map((l, i) => (
        <div key={l.name} style={{ height: 42, marginBottom: 8, display: "flex", alignItems: "center", gap: 12, padding: "0 14px", borderRadius: 10, background: i === idx ? "rgba(6,115,236,0.35)" : "transparent", border: i === idx ? `1.5px solid ${C.sky}` : "1.5px solid transparent", color: i === idx ? C.ink : C.dim, fontWeight: i === idx ? 700 : 500 }}>
          <span style={{ fontSize: 20 }}>{l.flag}</span>
          <span style={{ flex: 1 }}>{l.name}</span>
          <span style={{ color: C.green, fontSize: 14 }}>✓</span>
        </div>
      ))}
    </Section>
  );

  const bottom = (
    <div style={{ display: "flex", alignItems: "center", justifyContent: "center", gap: 22, height: "100%", fontSize: 58 }}>
      {LANGS.map((l, i) => (
        <div key={l.name} style={{ opacity: i === idx ? 1 : 0.35, transform: `scale(${i === idx ? 1.25 : 1})` }}>
          {l.flag}
        </div>
      ))}
    </div>
  );

  return (
    <AbsoluteFill>
      <Header num="04" title="Speak every language" sub="80+ locales, one project. Switch in a keystroke." />
      <div style={{ transform: `scale(${0.92 + 0.08 * pop(f, 0, 14, 140)})`, transformOrigin: `${L.panel.x + L.panel.w / 2}px ${L.panel.y + L.panel.h / 2}px`, position: "absolute", inset: 0 }}>
        <AppWindow inspector={inspector} bottom={bottom} locale={`${lang.flag} ${lang.name}`} localeHot={SWITCH.slice(1).some((s) => f >= s - 1 && f < s + 8) ? 1 : 0} zoom="54%">
          <div style={{ position: "absolute", left: rx, top: ry }}>
            <Row h={h} slots={SLOTS.slice(0, n)} bg={BGS.mint} tweak={() => ({ title: "" })} />
            {Array.from({ length: n }).map((_, i) => (
              <div key={i} style={{ position: "absolute", left: i * w + w * 0.04, top: h * 0.06, width: w * 0.92 }}>
                <Flip f={f} slot={i} size={w * 0.1} />
              </div>
            ))}
          </div>
        </AppWindow>
        <Pointer f={f} path={path} />
        {keycap && (
          <div style={{ position: "absolute", left: L.panel.x + (L.panel.w - L.inspector) / 2 - 90, top: L.panel.y + L.panel.h - 100, display: "flex", gap: 12, opacity: ease(f, [78, 84], [0, 1]) }}>
            {["⌘", "]"].map((k) => (
              <div key={k} style={{ width: 76, height: 76, borderRadius: 16, background: keyPress ? C.blue : "rgba(40,40,46,0.95)", border: `2px solid ${keyPress ? C.sky : C.line}`, boxShadow: keyPress ? "0 0 30px rgba(6,115,236,0.8)" : "0 6px 0 rgba(0,0,0,0.5)", transform: `translateY(${keyPress ? 4 : 0}px)`, display: "flex", alignItems: "center", justifyContent: "center", fontFamily: F.ui, fontSize: 36, fontWeight: 600, color: "#fff" }}>
                {k}
              </div>
            ))}
          </div>
        )}
      </div>
    </AbsoluteFill>
  );
};
