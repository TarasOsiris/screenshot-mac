import React from "react";
import { AbsoluteFill, Html5Audio, Sequence, staticFile } from "remotion";
import { Backdrop, CutFlash, SceneShell } from "./components/kit";
import { Intro, Outro } from "./scenes/Bookends";
import { Devices } from "./scenes/Devices";
import { Editor } from "./scenes/Editor";
import { Localize } from "./scenes/Localize";
import { Templates } from "./scenes/Templates";
import { Upload } from "./scenes/Upload";
import { CUTS, T } from "./theme";

type Move = "whip" | "zoom" | "fade" | "none";
const SCENES: { key: keyof typeof CUTS; C: React.FC; enter: Move; exit: Move }[] = [
  { key: "intro", C: Intro, enter: "none", exit: "zoom" },
  { key: "templates", C: Templates, enter: "zoom", exit: "zoom" },
  { key: "editor", C: Editor, enter: "zoom", exit: "whip" },
  { key: "devices", C: Devices, enter: "whip", exit: "whip" },
  { key: "localize", C: Localize, enter: "whip", exit: "whip" },
  { key: "upload", C: Upload, enter: "whip", exit: "zoom" },
  { key: "outro", C: Outro, enter: "zoom", exit: "none" },
];

// Every composition renders the same cut; scenes adapt to the aspect via useFmt().
export const Promo: React.FC = () => (
  <AbsoluteFill>
    <Backdrop />
    {SCENES.map(({ key, C, enter, exit }) => {
      const [a, b] = CUTS[key];
      return (
        <Sequence key={key} from={a - T} durationInFrames={b - a + 2 * T} name={key}>
          <SceneShell dur={b - a} enter={enter} exit={exit}>
            <C />
          </SceneShell>
        </Sequence>
      );
    })}
    {SCENES.slice(1).map(({ key }) => (
      <CutFlash key={key} at={CUTS[key][0]} />
    ))}
    <Html5Audio src={staticFile("audio/soundtrack.wav")} />
  </AbsoluteFill>
);
