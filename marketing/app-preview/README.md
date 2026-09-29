# App Store preview videos

Motion-designed app previews for iPhone, iPad and Mac, built in
[Remotion](https://www.remotion.dev) (React → video). Template previews, device-frame
PNGs, the logo and the DM Sans font are the app's own bundled assets
(`screenshot/Templates.bundle`, `screenshot/Assets.xcassets`), copied in by
`npm run assets`.

```sh
npm install
npm run assets   # copy templates/frames/logo/font from the app, synthesize the soundtrack
npm run studio   # live preview + scrubbing at localhost:3000 — edit src/ and it hot-reloads
npm run render   # → out/app-preview-iphone.mp4 (886x1920), out/app-preview-ipad.mp4 (1600x1200),
                 #   out/app-preview-mac.mp4 (1920x1080)
```

- **One cut, three layouts.** Every composition renders the same `Promo`; scenes read
  `useFmt()` and `LAYOUTS` in `src/components/kit.tsx` (headline and window placement per
  format). The editor chrome in `src/components/AppWindow.tsx` draws a Mac window with an
  inspector on desktop, an inspector split on iPad, and a bottom tool bar on iPhone.
- **Timing** lives in `src/theme.ts` (`CUTS`): scene boundaries on a 120 BPM grid
  (15 frames = one beat). `make-soundtrack.mjs` reads the same numbers, so after moving
  a cut re-run `npm run assets` to keep the whooshes on the cuts.
- **Scenes** are `src/scenes/*` — one file each, local frame 0 = the cut it enters on.
  Transitions in/out are owned by `SceneShell`.
- **Device frames** use the catalog insets from `DeviceFrameCatalogDefinitions.swift`
  (`FRAMES` in `src/components/Device.tsx`). The app inside them ("Habitly") is a mock.
- **Music** is synthesized (license-free). Swap in a licensed track by pointing
  `Html5Audio` in `src/Promo.tsx` at a file in `public/audio/`.
- App Store preview rules: 15–30 s, ≤30 fps, no pricing words, and no other platforms'
  names — which is why `prepare-assets.sh` skips the `google-play` template.
- `src/templates.gen.ts` is written by `prepare-assets.sh`; don't edit it by hand.
