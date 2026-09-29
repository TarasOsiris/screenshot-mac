import { Composition } from "remotion";
import { Promo } from "./Promo";
import { FPS, TOTAL } from "./theme";

export const Root = () => (
  <>
    {/* App Store app preview, iPhone 6.9"/6.5" — Apple's required 886x1920 portrait. */}
    <Composition id="AppPreview" component={Promo} width={886} height={1920} fps={FPS} durationInFrames={TOTAL} />
    {/* App Store app preview, iPad 13"/12.9" — 1600x1200 landscape. */}
    <Composition id="iPadPreview" component={Promo} width={1600} height={1200} fps={FPS} durationInFrames={TOTAL} />
    {/* Mac App Store app preview — 1920x1080. */}
    <Composition id="MacPreview" component={Promo} width={1920} height={1080} fps={FPS} durationInFrames={TOTAL} />
  </>
);
