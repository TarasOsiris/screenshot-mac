import { Composition } from "remotion";
import { CapturePreview } from "./capture/CapturePreview";
import { IPAD_CAPTIONS, IPHONE_CAPTIONS, MAC_CAPTIONS } from "./capture/captions";
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
    {/* Screen-capture previews (what App Review accepts): public/capture/*.mp4 cut from simulator recordings. */}
    <Composition id="iPadCapture" component={CapturePreview} width={1200} height={1600} fps={FPS} durationInFrames={788}
      defaultProps={{ src: "capture/ipad.mp4", bottom: 64, size: 44, captions: IPAD_CAPTIONS }} />
    <Composition id="iPhoneCapture" component={CapturePreview} width={886} height={1920} fps={FPS} durationInFrames={810}
      defaultProps={{ src: "capture/iphone.mp4", bottom: 150, size: 48, captions: IPHONE_CAPTIONS }} />
    <Composition id="MacCapture" component={CapturePreview} width={1920} height={1080} fps={FPS} durationInFrames={836}
      defaultProps={{ src: "capture/mac.mp4", bottom: 56, size: 44, captions: MAC_CAPTIONS }} />
  </>
);
