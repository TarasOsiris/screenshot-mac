import React from "react";
import { C, F } from "../theme";
import { useFmt, useLayout } from "./kit";

// The canvas area left inside the window once chrome is drawn.
export const useArea = () => {
  const L = useLayout();
  return { w: L.panel.w - L.inspector, h: L.panel.h - L.toolbar - L.bottom };
};

const Btn: React.FC<{ children: React.ReactNode; hot?: number; blue?: boolean; size: number }> = ({ children, hot = 0, blue, size }) => (
  <div
    style={{
      display: "flex",
      alignItems: "center",
      gap: 8,
      padding: `${size * 0.35}px ${size * 0.8}px`,
      borderRadius: 999,
      fontFamily: F.ui,
      fontWeight: 600,
      fontSize: size,
      color: C.ink,
      background: blue ? C.blue : `rgba(255,255,255,${0.08 + hot * 0.2})`,
      boxShadow: hot ? `0 0 ${24 * hot}px rgba(77,181,255,${hot})` : blue ? "0 4px 14px rgba(6,115,236,0.45)" : "none",
      border: hot ? `2px solid rgba(77,181,255,${hot})` : "2px solid transparent",
      whiteSpace: "nowrap",
    }}
  >
    {children}
  </div>
);

export const AppWindow: React.FC<{
  children: React.ReactNode;
  inspector?: React.ReactNode;
  bottom?: React.ReactNode;
  locale?: string;
  localeHot?: number;
  exportHot?: number;
  zoom?: string;
}> = ({ children, inspector, bottom, locale = "🇺🇸 English", localeHot = 0, exportHot = 0, zoom = "100%" }) => {
  const fmt = useFmt();
  const L = useLayout();
  const { panel, toolbar, inspector: iw, bottom: bh } = L;
  const fs = fmt === "desk" ? 18 : fmt === "pad" ? 21 : 28;
  return (
    <div
      style={{
        position: "absolute",
        left: panel.x,
        top: panel.y,
        width: panel.w,
        height: panel.h,
        borderRadius: fmt === "desk" ? 20 : fmt === "pad" ? 30 : 44,
        overflow: "hidden",
        background: C.win,
        border: `1.5px solid ${C.line}`,
        boxShadow: "0 40px 120px rgba(0,0,0,0.6), 0 0 100px rgba(6,115,236,0.22)",
      }}
    >
      <div style={{ position: "absolute", left: 0, right: 0, top: 0, height: toolbar, background: C.bar, borderBottom: `1px solid ${C.line}`, display: "flex", alignItems: "center", gap: 14, padding: `0 ${fmt === "phone" ? 26 : 20}px`, fontFamily: F.ui, color: C.ink }}>
        {fmt === "desk" && (
          <div style={{ display: "flex", gap: 9, marginRight: 14 }}>
            {["#FF5F57", "#FEBC2E", "#28C840"].map((c) => (
              <div key={c} style={{ width: 14, height: 14, borderRadius: 7, background: c }} />
            ))}
          </div>
        )}
        {fmt === "phone" ? (
          <div style={{ fontSize: fs * 1.3, color: C.sky, fontWeight: 500 }}>‹</div>
        ) : (
          <svg width={fs * 1.2} height={fs * 1.2} viewBox="0 0 24 24" fill="none" stroke="rgba(255,255,255,0.7)" strokeWidth="1.8">
            <rect x="3" y="4.5" width="18" height="15" rx="3" />
            <path d="M9 4.5 V19.5" />
          </svg>
        )}
        <div style={{ fontSize: fs, fontWeight: 700 }}>
          Habitly <span style={{ color: C.faint, fontWeight: 500 }}>▾</span>
        </div>
        {fmt !== "phone" && (
          <div style={{ margin: "0 auto", display: "flex", alignItems: "center", gap: 14, fontSize: fs * 0.95, color: C.dim }}>
            <span>−</span>
            <span style={{ color: C.ink, fontVariantNumeric: "tabular-nums" }}>{zoom}</span>
            <span>+</span>
          </div>
        )}
        <div style={{ marginLeft: fmt === "phone" ? "auto" : 0, display: "flex", gap: 10, alignItems: "center" }}>
          <Btn size={fs * 0.9} hot={localeHot}>
            {fmt === "phone" ? locale.split(" ")[0] : locale} <span style={{ color: C.faint }}>▾</span>
          </Btn>
          <div style={{ transform: `scale(${1 + exportHot * 0.08})` }}>
            <Btn size={fs * 0.9} blue>
              {fmt === "phone" ? "↑" : "Export"}
            </Btn>
          </div>
        </div>
      </div>
      <div style={{ position: "absolute", left: 0, top: toolbar, width: panel.w - iw, height: panel.h - toolbar - bh, background: C.well, overflow: "hidden" }}>{children}</div>
      {iw > 0 && (
        <div style={{ position: "absolute", right: 0, top: toolbar, width: iw, bottom: 0, background: "#232327", borderLeft: `1px solid ${C.line}`, overflow: "hidden", fontFamily: F.ui, color: C.ink }}>{inspector}</div>
      )}
      {bh > 0 && (
        <div style={{ position: "absolute", left: 0, right: 0, bottom: 0, height: bh, background: C.bar, borderTop: `1px solid ${C.line}`, fontFamily: F.ui, color: C.ink }}>{bottom}</div>
      )}
    </div>
  );
};

// Inspector building blocks, sized for the desktop column and scaled on iPad.
export const Section: React.FC<{ title: string; children: React.ReactNode; style?: React.CSSProperties }> = ({ title, children, style }) => {
  const fmt = useFmt();
  const s = fmt === "pad" ? 1.05 : 1;
  return (
    <div style={{ padding: `${18 * s}px ${20 * s}px`, borderBottom: `1px solid ${C.line}`, ...style }}>
      <div style={{ fontSize: 13 * s, fontWeight: 700, letterSpacing: 0.6, color: C.dim, textTransform: "uppercase", marginBottom: 12 * s }}>{title}</div>
      <div style={{ fontSize: 16 * s }}>{children}</div>
    </div>
  );
};

export const Segmented: React.FC<{ items: string[]; on: number; size?: number }> = ({ items, on, size = 15 }) => (
  <div style={{ display: "flex", background: "rgba(255,255,255,0.07)", borderRadius: 9, padding: 3 }}>
    {items.map((it, i) => (
      <div key={it} style={{ flex: 1, textAlign: "center", padding: "6px 0", borderRadius: 7, fontSize: size, fontWeight: 600, background: i === on ? "rgba(255,255,255,0.18)" : "transparent", color: i === on ? C.ink : C.dim }}>
        {it}
      </div>
    ))}
  </div>
);

export const Field: React.FC<{ label: string; value: React.ReactNode; hot?: boolean }> = ({ label, value, hot }) => (
  <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", padding: "7px 0" }}>
    <span style={{ color: C.dim }}>{label}</span>
    <span style={{ padding: "4px 10px", borderRadius: 7, background: hot ? "rgba(6,115,236,0.35)" : "rgba(255,255,255,0.07)", border: hot ? `1.5px solid ${C.sky}` : "1.5px solid transparent", fontVariantNumeric: "tabular-nums" }}>{value}</span>
  </div>
);

// The iPhone's bottom properties bar: a row of icon tools.
export const ToolBar: React.FC<{ tools: { icon: string; label: string }[]; hot?: string }> = ({ tools, hot }) => (
  <div style={{ display: "flex", justifyContent: "space-around", alignItems: "center", height: "100%", padding: "0 20px" }}>
    {tools.map((t) => {
      const on = t.label === hot;
      return (
        <div key={t.label} style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 10, color: on ? C.sky : "rgba(255,255,255,0.8)", fontSize: 24, fontWeight: 600 }}>
          <div style={{ width: 84, height: 84, borderRadius: 26, display: "flex", alignItems: "center", justifyContent: "center", fontSize: 38, background: on ? "rgba(6,115,236,0.35)" : "rgba(255,255,255,0.07)", border: on ? `2px solid ${C.sky}` : "2px solid transparent" }}>{t.icon}</div>
          {t.label}
        </div>
      );
    })}
  </div>
);

// A plain window (no editor toolbar): the template gallery and the upload flow.
export const Sheet: React.FC<{ title: string; children: React.ReactNode; right?: React.ReactNode }> = ({ title, children, right }) => {
  const fmt = useFmt();
  const { panel, toolbar } = useLayout();
  const fs = fmt === "desk" ? 18 : fmt === "pad" ? 21 : 28;
  return (
    <div style={{ position: "absolute", left: panel.x, top: panel.y, width: panel.w, height: panel.h, borderRadius: fmt === "desk" ? 20 : fmt === "pad" ? 30 : 44, overflow: "hidden", background: C.win, border: `1.5px solid ${C.line}`, boxShadow: "0 40px 120px rgba(0,0,0,0.6), 0 0 100px rgba(6,115,236,0.22)", fontFamily: F.ui, color: C.ink }}>
      <div style={{ height: toolbar, background: C.bar, borderBottom: `1px solid ${C.line}`, display: "flex", alignItems: "center", gap: 16, padding: "0 22px" }}>
        {fmt === "desk" && (
          <div style={{ display: "flex", gap: 9 }}>
            {["#FF5F57", "#FEBC2E", "#28C840"].map((c) => (
              <div key={c} style={{ width: 14, height: 14, borderRadius: 7, background: c }} />
            ))}
          </div>
        )}
        <div style={{ fontSize: fs, fontWeight: 700, flex: 1, textAlign: fmt === "desk" ? "center" : "left" }}>{title}</div>
        {right}
      </div>
      <div style={{ position: "absolute", left: 0, right: 0, top: toolbar, bottom: 0 }}>{children}</div>
    </div>
  );
};
