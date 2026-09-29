import { continueRender, delayRender, staticFile } from "remotion";

export const FPS = 30;

export const C = {
  bg: "#030814",
  ink: "#FFFFFF",
  dim: "rgba(255,255,255,0.58)",
  faint: "rgba(255,255,255,0.32)",
  blue: "#0673EC",
  sky: "#4DB5FF",
  cyan: "#3FE0FF",
  violet: "#7B61FF",
  pink: "#FF4F8B",
  yellow: "#FFD23F",
  green: "#2EE6A8",
  line: "rgba(255,255,255,0.12)",
  // macOS dark-mode chrome, which is what the editor draws in.
  win: "#1E1E22",
  bar: "#2A2A2E",
  well: "#141417",
  guide: "#FF2D8A",
};

export const F = {
  // DM Sans has no Cyrillic or CJK; Helvetica Neue must precede Hiragino, whose Cyrillic is full-width.
  display: `"DM Sans", "Helvetica Neue", "Hiragino Sans", "Apple SD Gothic Neo", sans-serif`,
  ui: "-apple-system, 'SF Pro Text', system-ui, sans-serif",
};

// Scene boundaries on the 120 BPM grid (one beat = 15 frames), so every cut lands
// on a kick in the soundtrack. The soundtrack script reads these same numbers.
export const CUTS = {
  intro: [0, 75],
  templates: [75, 195],
  editor: [195, 330],
  devices: [330, 465],
  localize: [465, 600],
  upload: [600, 765],
  outro: [765, 870],
} as const;

export const TOTAL = 870;

// Half the overlap each side of a cut, during which both scenes render.
export const T = 6;

const fonts: [string, string][] = [
  ["DM Sans", "DMSans.ttf"],
];

const handle = delayRender("fonts");
Promise.all(
  fonts.map(([family, file]) =>
    new FontFace(family, `url(${staticFile(`fonts/${file}`)})`, { weight: "100 1000" }).load().then((f) => {
      document.fonts.add(f);
    }),
  ),
).then(() => continueRender(handle));
