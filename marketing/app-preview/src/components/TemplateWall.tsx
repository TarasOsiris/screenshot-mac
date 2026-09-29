import React from "react";
import { Img, staticFile, useCurrentFrame } from "remotion";
import { TEMPLATE_NAMES } from "../templates.gen";

// Template previews are rows of screenshots at ~1.85:1.
export const PREVIEW_RATIO = 532 / 288;

export const Preview: React.FC<{ name: string; h: number; style?: React.CSSProperties }> = ({ name, h, style }) => (
  <Img src={staticFile(`templates/${name}.png`)} style={{ width: h * PREVIEW_RATIO, height: h, objectFit: "cover", borderRadius: h * 0.06, flexShrink: 0, ...style }} />
);

// Marquee rows of every bundled template, alternating direction.
export const TemplateWall: React.FC<{ rows: number; h: number; gap?: number; speed?: number; offset?: number; style?: React.CSSProperties }> = ({ rows, h, gap = 24, speed = 2.4, offset = 0 }) => {
  const f = useCurrentFrame();
  const cw = h * PREVIEW_RATIO + gap;
  const per = Math.ceil(TEMPLATE_NAMES.length / rows);
  return (
    <div style={{ display: "flex", flexDirection: "column", gap }}>
      {Array.from({ length: rows }).map((_, r) => {
        const names = Array.from({ length: per }).map((__, i) => TEMPLATE_NAMES[(r * per + i + offset) % TEMPLATE_NAMES.length]);
        const loop = per * cw;
        const x = (((r % 2 ? 1 : -1) * f * speed - r * cw * 0.5) % loop) - loop;
        return (
          <div key={r} style={{ display: "flex", gap, transform: `translateX(${x}px)` }}>
            {[...names, ...names, ...names].map((n, i) => (
              <Preview key={i} name={n} h={h} />
            ))}
          </div>
        );
      })}
    </div>
  );
};
