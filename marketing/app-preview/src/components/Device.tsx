import React from "react";
import { Img, staticFile } from "remotion";
import { F } from "../theme";

// Frame PNGs and screen insets straight from DeviceFrameCatalogDefinitions.swift.
export const FRAMES = {
  "iphone17pro-deepblue": { file: "iphone17pro-deepblue-portrait", w: 1350, h: 2760, l: 72, t: 69, r: 165, screen: "phone" },
  "iphone17pro-orange": { file: "iphone17pro-cosmicorange-portrait", w: 1350, h: 2760, l: 72, t: 69, r: 165, screen: "phone" },
  "iphone17-lavender": { file: "iphone17-lavender-portrait", w: 1350, h: 2760, l: 72, t: 69, r: 165, screen: "phone" },
  "iphoneair-white": { file: "iphoneair-cloudwhite-portrait", w: 1380, h: 2880, l: 60, t: 72, r: 165, screen: "phone" },
  "ipadpro13-gray": { file: "ipadpro13-spacegray-portrait", w: 2300, h: 3000, l: 118, t: 124, r: 54, screen: "pad" },
  "macbookair13-midnight": { file: "macbookair13-midnight-landscape", w: 3220, h: 2100, l: 330, t: 218, r: 0, screen: "mac" },
} as const;

export type FrameKind = keyof typeof FRAMES;
export type ScreenKind = "today" | "stats" | "focus" | "calendar";

export const frameAspect = (k: FrameKind) => FRAMES[k].h / FRAMES[k].w;

export const Device: React.FC<{ kind: FrameKind; width: number; screen?: ScreenKind; style?: React.CSSProperties }> = ({ kind, width, screen = "today", style }) => {
  const fr = FRAMES[kind];
  const k = width / fr.w;
  const sw = (fr.w - 2 * fr.l) * k;
  const sh = (fr.h - 2 * fr.t) * k;
  return (
    <div style={{ position: "relative", width, height: fr.h * k, ...style }}>
      <div style={{ position: "absolute", left: fr.l * k, top: fr.t * k, width: sw, height: sh, borderRadius: fr.screen === "mac" ? `${34 * k}px ${34 * k}px 0 0` : fr.r * k, overflow: "hidden", background: "#F4F5F9" }}>
        <Scaled base={fr.screen === "phone" ? 390 : fr.screen === "pad" ? 768 : 1280} width={sw} height={sh}>
          {fr.screen === "phone" ? <PhoneScreen kind={screen} /> : <DashScreen wide={fr.screen === "mac"} />}
        </Scaled>
      </div>
      <Img src={staticFile(`frames/${fr.file}.png`)} style={{ position: "absolute", inset: 0, width: "100%", height: "100%" }} />
    </div>
  );
};

const Scaled: React.FC<{ base: number; width: number; height: number; children: React.ReactNode }> = ({ base, width, height, children }) => {
  const s = width / base;
  return <div style={{ width: base, height: height / s, transform: `scale(${s})`, transformOrigin: "0 0" }}>{children}</div>;
};

const HABITS = [
  { e: "💧", n: "Drink water", s: "12 day streak", c: "#3FA9FF", done: true },
  { e: "🏃", n: "Morning run", s: "5 day streak", c: "#FF8A3D", done: true },
  { e: "📖", n: "Read 20 pages", s: "21 day streak", c: "#7B61FF", done: false },
  { e: "🧘", n: "Meditate", s: "8 day streak", c: "#2EC4A6", done: true },
  { e: "🌙", n: "Sleep by 11", s: "3 day streak", c: "#FF4F8B", done: false },
];

const Status: React.FC<{ dark?: boolean }> = ({ dark }) => (
  <div style={{ height: 54, display: "flex", alignItems: "center", justifyContent: "space-between", padding: "10px 34px 0", fontFamily: F.ui, fontWeight: 600, fontSize: 17, color: dark ? "#fff" : "#111" }}>
    <span>9:41</span>
    <span style={{ letterSpacing: 2, fontSize: 13 }}>●●● ▮</span>
  </div>
);

const Ring: React.FC<{ size: number; p: number; stroke: number; color: string; track?: string; children?: React.ReactNode }> = ({ size, p, stroke, color, track = "rgba(0,0,0,0.08)", children }) => {
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;
  return (
    <div style={{ position: "relative", width: size, height: size }}>
      <svg width={size} height={size} style={{ transform: "rotate(-90deg)" }}>
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke={track} strokeWidth={stroke} />
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke={color} strokeWidth={stroke} strokeLinecap="round" strokeDasharray={`${c * p} ${c}`} />
      </svg>
      <div style={{ position: "absolute", inset: 0, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center" }}>{children}</div>
    </div>
  );
};

const card: React.CSSProperties = { background: "#fff", borderRadius: 22, boxShadow: "0 4px 16px rgba(20,30,60,0.06)" };

const HabitRow: React.FC<{ h: (typeof HABITS)[number] }> = ({ h }) => (
  <div style={{ ...card, display: "flex", alignItems: "center", gap: 14, padding: "14px 16px", borderRadius: 18 }}>
    <div style={{ width: 44, height: 44, borderRadius: 14, background: `${h.c}22`, display: "flex", alignItems: "center", justifyContent: "center", fontSize: 22 }}>{h.e}</div>
    <div style={{ flex: 1 }}>
      <div style={{ fontFamily: F.ui, fontWeight: 600, fontSize: 17, color: "#111" }}>{h.n}</div>
      <div style={{ fontFamily: F.ui, fontSize: 13, color: "#8A8FA0", marginTop: 2 }}>{h.s}</div>
    </div>
    <div style={{ width: 30, height: 30, borderRadius: 15, background: h.done ? h.c : "transparent", border: h.done ? "none" : "2.5px solid #D5D8E2", color: "#fff", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 17, fontWeight: 700 }}>{h.done ? "✓" : ""}</div>
  </div>
);

const Title: React.FC<{ over: string; title: string; dark?: boolean }> = ({ over, title, dark }) => (
  <div style={{ padding: "14px 22px 16px" }}>
    <div style={{ fontFamily: F.ui, fontSize: 14, fontWeight: 600, color: dark ? "rgba(255,255,255,0.6)" : "#8A8FA0", textTransform: "uppercase", letterSpacing: 0.5 }}>{over}</div>
    <div style={{ fontFamily: F.ui, fontSize: 34, fontWeight: 800, color: dark ? "#fff" : "#111", marginTop: 2 }}>{title}</div>
  </div>
);

const Bars: React.FC<{ h: number }> = ({ h }) => (
  <div style={{ display: "flex", alignItems: "flex-end", gap: 12, height: h }}>
    {[0.55, 0.8, 0.45, 0.95, 0.7, 1, 0.62].map((v, i) => (
      <div key={i} style={{ flex: 1, display: "flex", flexDirection: "column", alignItems: "center", gap: 8 }}>
        <div style={{ width: "100%", height: (h - 26) * v, borderRadius: 8, background: i === 5 ? "linear-gradient(180deg,#4DB5FF,#0673EC)" : "#E3E8F4" }} />
        <div style={{ fontFamily: F.ui, fontSize: 12, color: "#8A8FA0" }}>{"MTWTFSS"[i]}</div>
      </div>
    ))}
  </div>
);

export const PhoneScreen: React.FC<{ kind: ScreenKind }> = ({ kind }) => {
  if (kind === "focus")
    return (
      <div style={{ height: "100%", background: "linear-gradient(180deg,#1B1450 0%,#3A1D8F 55%,#0673EC 130%)", color: "#fff" }}>
        <Status dark />
        <Title over="Focus" title="Deep work" dark />
        <div style={{ display: "flex", justifyContent: "center", marginTop: 40 }}>
          <Ring size={280} p={0.68} stroke={18} color="#7FD4FF" track="rgba(255,255,255,0.14)">
            <div style={{ fontFamily: F.ui, fontWeight: 300, fontSize: 64 }}>24:59</div>
            <div style={{ fontFamily: F.ui, fontSize: 16, opacity: 0.7 }}>of 40 min</div>
          </Ring>
        </div>
        <div style={{ display: "flex", justifyContent: "center", gap: 26, marginTop: 56 }}>
          {["↺", "❚❚", "✕"].map((g, i) => (
            <div key={g} style={{ width: i === 1 ? 84 : 64, height: i === 1 ? 84 : 64, borderRadius: "50%", background: i === 1 ? "#fff" : "rgba(255,255,255,0.14)", color: i === 1 ? "#3A1D8F" : "#fff", display: "flex", alignItems: "center", justifyContent: "center", fontSize: i === 1 ? 26 : 24, fontFamily: F.ui, fontWeight: 700 }}>
              {g}
            </div>
          ))}
        </div>
        <div style={{ margin: "56px 22px 0", padding: 18, borderRadius: 20, background: "rgba(255,255,255,0.1)", fontFamily: F.ui, fontSize: 16 }}>
          🎧 Rain & lo-fi · Do Not Disturb on
        </div>
      </div>
    );
  if (kind === "stats")
    return (
      <div style={{ height: "100%", background: "#F4F5F9" }}>
        <Status />
        <Title over="This week" title="Progress" />
        <div style={{ ...card, margin: "0 18px", padding: 20 }}>
          <div style={{ fontFamily: F.ui, fontWeight: 700, fontSize: 30, color: "#111" }}>86%</div>
          <div style={{ fontFamily: F.ui, fontSize: 14, color: "#34C759", fontWeight: 600, marginBottom: 16 }}>▲ 12% vs last week</div>
          <Bars h={170} />
        </div>
        <div style={{ display: "flex", gap: 14, margin: "14px 18px 0" }}>
          {[
            ["🔥", "21", "day streak"],
            ["✅", "134", "check-ins"],
          ].map(([e, v, l]) => (
            <div key={l} style={{ ...card, flex: 1, padding: 18 }}>
              <div style={{ fontSize: 24 }}>{e}</div>
              <div style={{ fontFamily: F.ui, fontWeight: 800, fontSize: 30, color: "#111", marginTop: 6 }}>{v}</div>
              <div style={{ fontFamily: F.ui, fontSize: 14, color: "#8A8FA0" }}>{l}</div>
            </div>
          ))}
        </div>
        <div style={{ ...card, margin: "14px 18px", padding: 18, display: "grid", gridTemplateColumns: "repeat(14, 1fr)", gap: 5 }}>
          {Array.from({ length: 56 }).map((_, i) => (
            <div key={i} style={{ aspectRatio: "1", borderRadius: 4, background: `rgba(6,115,236,${[0.12, 0.35, 0.6, 0.9][(i * 7 + (i >> 2)) % 4]})` }} />
          ))}
        </div>
      </div>
    );
  if (kind === "calendar")
    return (
      <div style={{ height: "100%", background: "#F4F5F9" }}>
        <Status />
        <Title over="2026" title="September" />
        <div style={{ ...card, margin: "0 18px", padding: 18 }}>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(7, 1fr)", gap: 8, textAlign: "center", fontFamily: F.ui }}>
            {"MTWTFSS".split("").map((d, i) => (
              <div key={i} style={{ fontSize: 12, color: "#8A8FA0", fontWeight: 600 }}>{d}</div>
            ))}
            {Array.from({ length: 30 }).map((_, i) => {
              const on = (i * 5) % 7 !== 3 && i < 29;
              return (
                <div key={i} style={{ height: 40, borderRadius: 12, display: "flex", alignItems: "center", justifyContent: "center", fontSize: 15, fontWeight: 600, background: i === 28 ? "#0673EC" : on ? "#E6F0FD" : "transparent", color: i === 28 ? "#fff" : "#1B2340" }}>
                  {i + 1}
                </div>
              );
            })}
          </div>
        </div>
        <div style={{ margin: "14px 18px 0", display: "flex", flexDirection: "column", gap: 10 }}>
          {HABITS.slice(0, 2).map((h) => (
            <HabitRow key={h.n} h={h} />
          ))}
        </div>
      </div>
    );
  return (
    <div style={{ height: "100%", background: "#F4F5F9" }}>
      <Status />
      <Title over="Tuesday, Sep 29" title="Today" />
      <div style={{ ...card, margin: "0 18px", padding: 20, display: "flex", alignItems: "center", gap: 22 }}>
        <Ring size={116} p={0.72} stroke={14} color="#0673EC">
          <div style={{ fontFamily: F.ui, fontWeight: 800, fontSize: 26, color: "#111" }}>72%</div>
        </Ring>
        <div>
          <div style={{ fontFamily: F.ui, fontWeight: 700, fontSize: 20, color: "#111" }}>5 of 7 done</div>
          <div style={{ fontFamily: F.ui, fontSize: 15, color: "#8A8FA0", marginTop: 4 }}>Keep going — you're on a roll!</div>
        </div>
      </div>
      <div style={{ margin: "16px 18px 0", display: "flex", flexDirection: "column", gap: 10 }}>
        {HABITS.map((h) => (
          <HabitRow key={h.n} h={h} />
        ))}
      </div>
    </div>
  );
};

// The iPad / Mac layout of the same app: habits beside the weekly chart.
const DashScreen: React.FC<{ wide: boolean }> = ({ wide }) => (
  <div style={{ height: "100%", background: "#F4F5F9", display: "flex" }}>
    {wide && (
      <div style={{ width: 230, background: "#E9ECF4", padding: "46px 18px", fontFamily: F.ui, fontSize: 16, color: "#1B2340", display: "flex", flexDirection: "column", gap: 6 }}>
        {["Today", "Progress", "Focus", "Calendar"].map((n, i) => (
          <div key={n} style={{ padding: "9px 12px", borderRadius: 9, background: i === 0 ? "#0673EC" : "transparent", color: i === 0 ? "#fff" : "#1B2340", fontWeight: 600 }}>
            {n}
          </div>
        ))}
      </div>
    )}
    <div style={{ flex: 1, padding: wide ? "20px 10px" : "20px 12px" }}>
      {!wide && <Status />}
      <Title over="Tuesday, Sep 29" title="Today" />
      <div style={{ display: "flex", gap: 18, padding: "0 12px" }}>
        <div style={{ flex: 1, display: "flex", flexDirection: "column", gap: 10 }}>
          {HABITS.map((h) => (
            <HabitRow key={h.n} h={h} />
          ))}
        </div>
        <div style={{ flex: 1, display: "flex", flexDirection: "column", gap: 14 }}>
          <div style={{ ...card, padding: 20, display: "flex", alignItems: "center", gap: 20 }}>
            <Ring size={110} p={0.72} stroke={13} color="#0673EC">
              <div style={{ fontFamily: F.ui, fontWeight: 800, fontSize: 24, color: "#111" }}>72%</div>
            </Ring>
            <div style={{ fontFamily: F.ui, fontWeight: 700, fontSize: 19, color: "#111" }}>5 of 7 done</div>
          </div>
          <div style={{ ...card, padding: 20 }}>
            <Bars h={wide ? 200 : 260} />
          </div>
        </div>
      </div>
    </div>
  </div>
);
