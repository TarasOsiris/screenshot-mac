import React from "react";
import { AbsoluteFill } from "remotion";
import { AppWindow, Field, Section, Segmented, ToolBar, useArea } from "../components/AppWindow";
import { ease, Header, INOUT, pop, Pointer, Selection, useFmt, useLayout, useSceneFrame, Way } from "../components/kit";
import { BGS, deviceBox, gradient, Row, TEMPLATE_RATIO, Tweak } from "../components/Row";
import { C } from "../theme";

const NEW_TITLE = "Build habits\nthat stick";
const TOOLS = [
  { icon: "T", label: "Text" },
  { icon: "▢", label: "Shape" },
  { icon: "▯", label: "Device" },
  { icon: "◐", label: "Fill" },
  { icon: "⧉", label: "Align" },
];
const PRESETS = [BGS.brand, BGS.sunset, BGS.mint, { stops: ["#111", "#3A3A44"], angle: 160 }, { stops: ["#FFB23F", "#FF6A3D"], angle: 140 }];

// Beats (scene-local frames).
const TEXT_AT = 26;
const DEVICE_AT = 62;
const BG_AT = 100;

export const Editor: React.FC = () => {
  const f = useSceneFrame();
  const fmt = useFmt();
  const L = useLayout();
  const area = useArea();
  const phone = fmt === "phone";
  const h = phone ? 1000 : Math.min(area.h - 70, (area.w - 80) / (4 * TEMPLATE_RATIO));
  const w = h * TEMPLATE_RATIO;
  const rowW = 4 * w;
  // iPhone pans the row: title first, then the device in the second screenshot.
  const pan = phone ? ease(f, [48, 62], [24, area.w / 2 - 1.5 * w], INOUT) : 0;
  const rx = phone ? pan : (area.w - rowW) / 2;
  const ry = (area.h - h) / 2;

  const typed = f < TEXT_AT + 6 ? "Your title\nhere" : NEW_TITLE.slice(0, Math.floor(ease(f, [TEXT_AT + 6, TEXT_AT + 30], [0, NEW_TITLE.length], (t) => t)));
  const caret = f >= TEXT_AT + 4 && f < DEVICE_AT && Math.floor(f / 4) % 2 === 0;
  const slide = ease(f, [DEVICE_AT + 4, DEVICE_AT + 20], [-0.17, 0], INOUT);
  const rot = ease(f, [DEVICE_AT + 24, DEVICE_AT + 34], [0, -7], INOUT);
  const tw1: Tweak = { dx: slide * w, rot };
  const tweak = (i: number): Tweak => (i === 0 ? { title: typed + (caret ? "|" : "") } : i === 1 ? tw1 : {});
  const bgMix = ease(f, [BG_AT + 4, BG_AT + 20], [0, 1], INOUT);
  const phase = f < TEXT_AT ? "none" : f < DEVICE_AT ? "text" : f < BG_AT - 4 ? "device" : "bg";

  // Screen-space origins of the canvas and inspector, for the pointer.
  const cx0 = L.panel.x;
  const cy0 = L.panel.y + L.toolbar;
  const ix0 = L.panel.x + L.panel.w - L.inspector;
  const db = deviceBox(h, 1, tw1);
  const d0 = deviceBox(h, 1, { dx: -0.17 * w });
  const d1 = deviceBox(h, 1);
  const titleBox = { x: rx + w * 0.05, y: ry + h * 0.055, w: w * 0.9, h: w * 0.27 };
  const swatch = 44;
  const swY = 470;
  const swatchAt = (i: number) => ({ x: ix0 + 20 + i * (swatch + 12) + swatch / 2, y: cy0 + swY + swatch / 2 });
  const popH = 150;
  const phoneSwatch = (i: number) => ({ x: cx0 + 60 + i * 150 + 50, y: cy0 + area.h - popH / 2 - 10 });
  const toolAt = (label: string) => ({ x: cx0 + 20 + ((L.panel.w - 40) / TOOLS.length) * (TOOLS.findIndex((t) => t.label === label) + 0.5), y: cy0 + area.h + 75 });

  const path: Way[] = [
    { at: 0, x: cx0 + area.w * 0.7, y: cy0 + area.h * 0.85 },
    { at: TEXT_AT - 2, x: cx0 + titleBox.x + titleBox.w * 0.5, y: cy0 + titleBox.y + titleBox.h * 0.4 },
    { at: TEXT_AT + 2, x: cx0 + titleBox.x + titleBox.w * 0.5, y: cy0 + titleBox.y + titleBox.h * 0.4, click: true },
    ...(phone ? [{ at: TEXT_AT + 20, x: cx0 + area.w * 0.8, y: cy0 + area.h * 0.9 }] : []),
    { at: DEVICE_AT, x: cx0 + rx + d0.x + d0.w * 0.5, y: cy0 + ry + d0.y + d0.h * 0.3, click: true },
    { at: DEVICE_AT + 20, x: cx0 + rx + d1.x + d1.w * 0.5, y: cy0 + ry + d1.y + d1.h * 0.3 },
    ...(phone
      ? [
          { at: BG_AT - 8, x: toolAt("Fill").x, y: toolAt("Fill").y },
          { at: BG_AT - 4, x: toolAt("Fill").x, y: toolAt("Fill").y, click: true },
          { at: BG_AT + 2, x: phoneSwatch(1).x, y: phoneSwatch(1).y, click: true },
          { at: BG_AT + 26, x: phoneSwatch(1).x + 60, y: phoneSwatch(1).y + 30 },
        ]
      : [
          { at: BG_AT - 2, x: swatchAt(1).x, y: swatchAt(1).y },
          { at: BG_AT + 2, x: swatchAt(1).x, y: swatchAt(1).y, click: true },
          { at: BG_AT + 26, x: swatchAt(1).x + 40, y: swatchAt(1).y + 60 },
        ]),
  ];

  const bgNow = bgMix < 0.5 ? BGS.brand : BGS.sunset;
  const inspector = (
    <div style={{ position: "relative", height: "100%" }}>
      <Section title="Row">
        <Field label="Size" value="iPhone 6.9″" />
        <Field label="Screenshots" value="4" />
      </Section>
      <div style={{ height: 250 }}>
        {phase === "text" && (
          <Section title="Text" style={{ borderBottom: "none" }}>
            <Field label="Font" value="DM Sans" hot />
            <Field label="Size" value="140 pt" />
            <Field label="Weight" value="Bold" />
            <Field label="Align" value="Center" />
          </Section>
        )}
        {(phase === "device" || phase === "bg") && (
          <Section title="Device" style={{ borderBottom: "none", opacity: phase === "bg" ? 0.5 : 1 }}>
            <Field label="Frame" value="iPhone 17 Pro" />
            <Field label="X" value={Math.round(96 + slide * 1290)} hot={f < DEVICE_AT + 22} />
            <Field label="Rotation" value={`${Math.round(rot)}°`} hot={f >= DEVICE_AT + 22 && phase === "device"} />
            <Field label="Shadow" value="On" />
          </Section>
        )}
      </div>
      <div style={{ position: "absolute", left: 0, right: 0, top: 350 }}>
        <Section title="Background">
          <Segmented items={["Color", "Gradient", "Image"]} on={1} />
          <div style={{ position: "relative", height: 22, borderRadius: 11, marginTop: 16, overflow: "hidden" }}>
            <div style={{ position: "absolute", inset: 0, background: gradient({ ...BGS.brand, angle: 90 }) }} />
            <div style={{ position: "absolute", inset: 0, background: gradient({ ...BGS.sunset, angle: 90 }), opacity: bgMix }} />
          </div>
          <div style={{ display: "flex", justifyContent: "space-between", marginTop: -30, padding: "0 2px" }}>
            {bgNow.stops.map((c, i) => (
              <div key={i} style={{ width: 22, height: 22, borderRadius: 11, border: "3px solid #fff", background: c, boxShadow: "0 2px 6px rgba(0,0,0,0.5)", marginTop: 34 }} />
            ))}
          </div>
          <div style={{ display: "flex", gap: 12, marginTop: 34 }}>
            {PRESETS.map((p, i) => (
              <div key={i} style={{ width: swatch, height: swatch, borderRadius: 12, background: gradient(p), border: i === (bgMix > 0.5 ? 1 : 0) ? "3px solid #fff" : "3px solid transparent", boxShadow: i === 1 && f >= BG_AT ? `0 0 ${20 * (1 - bgMix * 0.5)}px ${C.pink}` : "none" }} />
            ))}
          </div>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginTop: 22 }}>
            <span>Stretch across all screenshots</span>
            <div style={{ width: 40, height: 24, borderRadius: 12, background: C.blue, position: "relative" }}>
              <div style={{ position: "absolute", right: 2, top: 2, width: 20, height: 20, borderRadius: 10, background: "#fff" }} />
            </div>
          </div>
        </Section>
      </div>
    </div>
  );

  const hot = phase === "text" ? "Text" : phase === "device" ? "Device" : phase === "bg" ? "Fill" : undefined;
  const guide = f >= DEVICE_AT + 14 && f < DEVICE_AT + 36;

  return (
    <AbsoluteFill>
      <Header num="02" title="Design them all at once" sub="One canvas. Shapes and gradients flow across." />
      <div style={{ transform: `scale(${0.92 + 0.08 * pop(f, 0, 14, 140)})`, transformOrigin: `${L.panel.x + L.panel.w / 2}px ${L.panel.y + L.panel.h / 2}px`, position: "absolute", inset: 0 }}>
        <AppWindow inspector={inspector} bottom={<ToolBar tools={TOOLS} hot={hot} />} zoom={phone ? "100%" : "62%"}>
          <div style={{ position: "absolute", left: rx, top: ry }}>
            <Row h={h} bg={BGS.brand} bgB={BGS.sunset} bgMix={bgMix} tweak={tweak} />
            {phase === "text" && <Selection {...titleBox} x={titleBox.x - rx} y={titleBox.y - ry} opacity={ease(f, [TEXT_AT, TEXT_AT + 4], [0, 1])} />}
            {phase === "device" && <Selection x={db.x} y={db.y} w={db.w} h={db.h} rot={rot} origin="50% 30%" />}
            {guide && (
              <>
                <div style={{ position: "absolute", left: 1.5 * w - 1, top: 0, height: h, width: 2, background: C.guide, opacity: ease(f, [DEVICE_AT + 14, DEVICE_AT + 18], [0, 1]) }} />
                <div style={{ position: "absolute", left: 1.5 * w + 8, top: h * 0.2, padding: "3px 8px", borderRadius: 6, background: C.guide, color: "#fff", fontSize: phone ? 24 : 15, fontWeight: 700 }}>centered</div>
              </>
            )}
          </div>
          {phone && (
            <div
              style={{
                position: "absolute",
                left: 30,
                right: 30,
                bottom: 10,
                height: popH,
                borderRadius: 30,
                background: "rgba(40,40,46,0.96)",
                border: `1px solid ${C.line}`,
                display: "flex",
                alignItems: "center",
                gap: 50,
                padding: "0 30px",
                transform: `translateY(${(1 - ease(f, [BG_AT - 4, BG_AT + 4], [0, 1])) * (popH + 20)}px)`,
              }}
            >
              {PRESETS.map((p, i) => (
                <div key={i} style={{ width: 100, height: 100, borderRadius: 26, background: gradient(p), border: i === (bgMix > 0.5 ? 1 : 0) ? "5px solid #fff" : "5px solid transparent" }} />
              ))}
            </div>
          )}
        </AppWindow>
        <Pointer f={f} path={path} />
      </div>
    </AbsoluteFill>
  );
};

