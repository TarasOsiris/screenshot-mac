# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Screenshot Bro — app for generating App Store & Google Play screenshots with device frames, shapes, and a multi-row editor. Swift + SwiftUI. **Multiplatform: macOS (primary) + iPadOS/iOS** from a single target. Integrates RevenueCat (in-app purchases), SwiftDraw (SVG rendering), and can upload finished screenshots directly to App Store Connect.

## Code Style

- **Comment sparingly — default to no comment.** Well-named code is self-documenting; do not narrate what it already says (no `// loop over rows`, no restating a modifier). Add a comment *only* when the reader would otherwise be misled or waste time: a non-obvious workaround, a platform quirk, an invariant, or a "why this and not the obvious alternative." When you do comment, write one concise line — never a multi-line paragraph explaining mechanics. If you feel the need to explain *how* the code works, rename or restructure it instead.

## UX Reference

Sketch is the main reference project. UX patterns (cursors, handles, interactions, inspector behavior, etc.) should follow Sketch conventions when applicable.

## Build

Project: `screenshot.xcodeproj` (no workspace). Scheme: `screenshot`. Targets: `screenshot` (app), `screenshotTests` (unit tests). `SUPPORTED_PLATFORMS = iphoneos iphonesimulator macosx`, `TARGETED_DEVICE_FAMILY = 1,2`; macOS deployment 15.0, iOS deployment 18.0. Dependencies via Xcode-managed SPM: RevenueCat `purchases-ios-spm` (5.0+) and SwiftDraw (0.27+).

Build (macOS is the primary dev target):
```
xcodebuild -scheme screenshot -destination 'platform=macOS' build
```

Run unit tests (always kill the running app first to avoid Xcode crash/hang — a PreToolUse hook also does this automatically):
```
killall screenshot 2>/dev/null; xcodebuild -scheme screenshot -destination 'platform=macOS' test
```

Tests in `screenshotTests/` cover `AppState` (operations, locale, deletion), `ExportService` rendering, `CanvasShapeModel`, `ScreenshotRow`, `AlignmentService`, `LocaleService`, `ProjectMerge` (iCloud merge), `DeviceFrameCatalog`, `TemplateService`, `SvgHelper`, `RichTextUtils`, and the App Store Connect auth/display-type/upload-validator services. No linter configured.

Because the code is multiplatform, also compile the iOS branches after touching anything platform-conditional (`#if os` / `Platform/` shims) — a clean macOS build does not prove the iOS branch builds:
```
xcodebuild -scheme screenshot -destination 'generic/platform=iOS Simulator' build
```

**SourceKit per-file diagnostics are unreliable here** — it routinely reports phantom `Cannot find type … in scope` / `Cannot find 'UIMetrics' in scope` for symbols defined in sibling files. Trust the result of `xcodebuild`, not the editor diagnostics; only act on errors a full build actually reports.

Shipping (via the `ship` skill) targets both platforms from the one `ExportOptions.plist` (`method: app-store-connect`): archive macOS with `-destination 'platform=macOS,arch=arm64'` and iOS with `-destination 'generic/platform=iOS'`, then `-exportArchive` with the plist's `destination` flipped from `export` to `upload` and reverted after. `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` appear 4× each in `project.pbxproj` (Debug/Release × app/tests) — bump all with `replace_all`.

## Skills, Agents & Harness

Custom Claude Code skills live in `.claude/skills/`:
- `gen-project-schema` — regenerate `tools/project-schema.json` from the Swift Codable models after any change to the on-disk JSON shape.
- `regression-checklist` — structured pre-commit walk of the Regression Prevention section below.
- `ship` — bump build/marketing version, build, and upload to App Store Connect.
- `import-svg-template` / `project-to-template` — create bundled templates from SVGs or existing projects.
- `add-localized-string` — add user-facing strings and propagate translations via the Python scripts (see below). **Never hand-edit `Localizable.xcstrings`** — a PreToolUse hook blocks it; it is generated. Gotcha: the catalog is committed in Xcode's serialization (`"k" : "v"`, space before the colon) but `translate_catalog.py` / `translate_popular_languages.py` rewrite the entire file in `json.dumps` style (`"k": "v"`), and `xcodebuild` does **not** renormalize it — so running the scripts wholesale yields a ~35k-line cosmetic diff (and opportunistically fills unrelated missing translations). To add one string's translations cleanly, generate them with the scripts, then inject just that key into the catalog in the existing Xcode format instead of committing the reflowed file.
- `swiftui-patterns` / `swiftui-pro` — macOS SwiftUI reference + review.

Reviewer/build agents in `.claude/agents/`: `export-parity-reviewer` (visual/export parity, coordinate space, Codable persistence, enum switch coverage), `xcode-build-validator` (runs xcodebuild, reports result). `/gwip` (stage+commit WIP+push) is a global command.

`.codex/` mirrors the hooks and agent definitions for the cloud (Codex) harness; `AGENTS.md` is the agent registry. `tools/` holds Python utilities: `gen_template.py` (SVG→template), `translate_catalog.py` + `translate_popular_languages.py` (localization), and `project-schema.json` (JSON Schema for `project.json`).

## Git Workflow

When I say 'push', always commit first if there are uncommitted changes, then push. Never say 'nothing to push' if there are uncommitted changes.

## Build & Architecture

SwiftUI app, macOS-first with an iPad/iOS build sharing the same code. Always verify builds pass after changes with `xcodebuild`. Be cautious with NSViewRepresentable overlays as they can break scrolling, and .position()/.offset() swaps cause visual regressions. AppKit-only APIs must be guarded behind `#if os(macOS)` and routed through the `Platform/` shims (see below).

## Testing & Verification

After implementing a fix, verify it covers ALL variants: image-based frames, clipped mode, rotated elements, dark mode, and export/preview parity. Don't assume a fix for one case covers all cases.

## Architecture

**Source layout:** All Swift source lives under `screenshot/Code/`:
- `App/` — `AppState` (split across `AppState+*` extensions) + app entry + window management.
- `Models/` — data model structs/enums.
- `Services/` — business logic (persistence, export, locale, alignment, iCloud, store, SVG, App Store Connect, simulator capture, etc.).
- `Platform/` — cross-platform shims that let macOS-first code (`NSImage`/`NSColor`/`NSFont`…) compile on iOS.
- `DeviceFrames/` — `Models/`, `Rendering/`, `UI/` for device-frame rendering (2D PNG specs + SceneKit 3D models).
- `Views/` — `Canvas/`, `Editor/`, `Export/`, `Inspector/`, `Settings/`, `Toolbar/`, plus top-level shell views.
- `Extensions/`.

Bundled resources in `screenshot/`: `Templates.bundle` (35+ starter themes), `SvgPresets.bundle` (SVG shapes for `SvgPresetCatalog`), `DeviceModels/` (USDZ 3D models, e.g. iPhone 17 Pro / Pro Max), `Assets.xcassets`.

**Platform abstraction (`Platform/`):**
- `PlatformAliases.swift` — on iOS, `typealias NSImage = UIImage`, `NSColor = UIColor`, `NSFont = UIFont`, plus `NSSize/NSRect/NSPoint`. macOS-first call sites compile unchanged; AppKit-only drawing/window/event APIs stay guarded by `#if os(macOS)`.
- `PlatformFont.swift`, `PlatformImageShims.swift` — the slice of AppKit API the code actually calls, reimplemented for UIKit.
- `PlatformInput.swift` — `PlatformModifiers` (live shift/option flags on macOS; off on iPad, so shift-constrain / option-duplicate are macOS-only).

**App entry:** `screenshotApp.swift` — injects `AppState` into the SwiftUI environment via `@State` + `.environment()`. Defines keyboard shortcuts and menu items (Edit, View, Locale, Debug). `AppWindowManager` handles standalone windows (new-project, etc.).

**State management:** `AppState` (`@Observable`) is the single source of truth, split across extension files: `AppState+Images`, `+BackgroundImages`, `+ImageResources`, `+Locales`, `+Persistence`, `+Projects`, `+Rows`, `+Selection`, `+Shapes`, `+Templates`, `+Zoom`, `+CustomFonts`, `+Coach` (onboarding), `+SimulatorCapture`. All mutations go through AppState methods, which call `scheduleSave()` to debounce persistence (0.3s). Undo/redo via macOS `UndoManager`.

**Data model hierarchy:**
- `Project` → has many `ScreenshotRow` (stored in `ProjectData`). Supports soft deletion (tombstones) with `isDeleted`/`deletedAt` and `merged(with:)` for iCloud conflict resolution; `purgingOldTombstones()` removes tombstones older than 30 days.
- `ScreenshotRow` → `templates: [ScreenshotTemplate]` (columns) + `shapes: [CanvasShapeModel]` (canvas elements). Implements `BackgroundFillable`.
- `ScreenshotTemplate` → per-column background/gradient settings. Implements `BackgroundFillable`.
- `CanvasShapeModel` → union type via `ShapeType` (rectangle, circle, star, text, image, device, svg). Type-specific properties are optionals on the same struct, including device `ShadowConfig`, `DeviceBodyMaterial`, and `DeviceLighting` for 3D frames.
- `ScreenshotSize` — width/height/subtitle preset describing a target screenshot dimension (portrait/landscape labels).
- `TextStyle` / `TextAlign` / `TextVerticalAlign` — text-shape styling fields. Rich text is persisted as Base64-RTF (see `RichTextUtils`).
- `ShadowConfig` — configurable drop shadow (model-space `radius`/`offsetX`/`offsetY`, multiplied by `displayScale` at render time for parity). All fields optional → old projects decode to "no shadow".
- `DeviceBodyMaterial` (matte/glossy finish) + `DeviceLighting` (ambient/key/rim intensities) — per-shape 3D device appearance. Optional fields with defaults.
- `BackgroundStyle` → enum (color, gradient, image) with `GradientConfig` (color stops, angle, type, center) and `BackgroundImageConfig` (fileName, svgContent, fillMode, opacity, tileSpacingX/Y, tileOffsetX/Y, tileScaleX/Y). `BackgroundFillable` protocol provides `backgroundFillView(image:modelSize:)` and `resolvedBackgroundView(screenshotImages:modelSize:)`.
- `ImageFillMode` → enum (fill, fit, stretch, tile). Tile uses canvas-based rendering with configurable spacing/offset/scale.
- `GradientType` → enum (linear, radial, angular). Linear uses `LinearGradient` with angle-derived start/end points. Radial draws a `Canvas` `.radialGradient` shading whose `endRadius` is derived from the Canvas draw size (Canvas exposes its size synchronously — `GeometryReader` was unreliable because its size-dependent child isn't resolved before an offscreen snapshot captures, leaving backgrounds blank in export). Angular uses `AngularGradient` with center and angle offset.
- `DeviceCategory` → enum (iphone, ipadPro11, ipadPro13, macbook, androidPhone, **pixel9**, androidTablet, invisible). `invisible` provides abstract layout with no visible frame.
- `DeviceFrame` / `DeviceFrameCatalog` (`DeviceFrameCatalogDefinitions`, `DeviceFrameModels`) → real device frame PNG specs (iPhone 17/Air/Pro/Pro Max, iPad Pro 11"/13", MacBook Air 13"/Pro 14"/Pro 16", iMac 24") with per-color variants and landscape support. `DeviceFrameImageSpec` defines screen insets/corner radii; `DeviceFrameModelSpec` defines 3D model resources for SceneKit rendering.
- `LocaleState` (`LocaleModels`) → locale definitions + active locale + per-shape overrides (`ShapeLocaleOverride` for text properties). `LocalePresets` has 30 language definitions.
- `ShowcaseExportConfig` (`ShowcaseExport`) → marketing-showcase layout (spacing/padding/corner-radius percentages, aspect-ratio + output-size presets) implementing `BackgroundFillable`.
- `OnboardingCoach` → `OnboardingCoachStep` coach-mark sequence (canvas → inspector → shapes → locale → export) + `OnboardingPersistence` UserDefaults keys.
- `CustomFont` — metadata for user-imported font files. `AlignmentGuide` — snap guide line model.

**Services:**
- `PersistenceService` — JSON files in `~/Library/Application Support/screenshot/`. Index at `projects.json`, per-project data at `projects/<uuid>/project.json`, images in `projects/<uuid>/resources/`. `SCREENSHOT_DATA_DIR` env override for tests.
- `ExportService` / `ExportImageEncoder` — render templates to PNG/JPEG via SwiftUI `ImageRenderer` at configurable scale (1x–3x). Multi-locale export creates locale subfolders; multi-row creates row-label subfolders. Also powers showcase export and thumbnails. `ExportImageEncoder` does the final NSImage→PNG/JPEG encoding (with iOS branch).
- `ProjectThumbnailService` — renders a cached snapshot of a project's first row (through the shared export path) for project cards.
- `LocaleService` — resolves shapes with locale overrides. `splitUpdate()` separates base shape mutations from locale-specific text. Base locale is first; non-base locales get text-only overrides.
- `AlignmentService` — snap-to-grid alignment against other shapes and template boundaries (4px threshold); returns snap deltas + guide lines.
- `ICloudSyncService` / `ICloudMonitor` — iCloud Drive sync (container `iCloud.xyz.tleskiv.screenshot`); last-writer-wins merge with tombstone awareness, `NSFileCoordinator`, `NSFilePresenter` watching, `NSMetadataQuery` progress, 1s debounced reload, own-write detection.
- `StoreService` — RevenueCat Pro tier. Free tier: 1 project (cannot create additional), 3 rows/project, 5 templates/row. `PaywallContext` provides context-aware messages.
- `SvgHelper` / `SvgPresetCatalog` — SVG sanitize (strip scripts/handlers), `parseSize`, `scaledSize`, render to image (via SwiftDraw) with optional color replacement; `SvgPresetCatalog` loads the bundled preset shapes.
- `RichTextUtils` — encode/decode `NSAttributedString` ↔ Base64-RTF for text-shape persistence, plus per-property style application.
- `BackgroundRemovalService` — Vision foreground-mask request to make an image's background transparent.
- `SimulatorCaptureService` (DEBUG, macOS) — captures iOS Simulator screenshots via a user-installed helper script run through `NSUserUnixTask` (sandbox-safe escape hatch for `xcrun simctl`).
- App Store Connect suite — `AppStoreConnectAuthService` / `…CredentialsStore` / `…APIService` / `…UploadService` / `…UploadValidator` / `…IconFetcher` / `…DisplayType` / `…DemoData`, backed by `KeychainService` for secret storage. Uploads exported screenshots to App Store Connect.
- `NotificationService` — user notifications for completed long tasks (no-ops when frontmost).
- `TemplateService`, `ExportFolderService`, `DebugTemplateService`, `QuickLookCoordinator`, `AppLogger`.

**View hierarchy** (under `Views/`):
- Shell (top level): `AppRootView` → `ContentView` (toolbar: project selector, zoom, locale menu, export; vertical scroll of rows; bottom shape-properties bar; right inspector). `ProjectsView` (project home/cards), `NewProjectWindowView`, `ProjectNameSheet`, `OnboardingView`, `ProjectLoadingOverlay`, `HelpView`, `IPadSettingsView`, `DefaultsPickers` (settings), `PaywallSheetContent` / `PostPurchaseCelebrationView` (store), `CoachPopover` (onboarding coach marks), `ActionButton`, `UIMetrics`, `DebugProjectManagerView`, `ContentExportControl`.
- `Export/` — `ShowcaseExportSheet`, `ShowcaseRowView`; App Store Connect upload UI: `UploadToAppStoreConnectView`, `UploadToAppStoreConnectSelectionSteps`, `AppStoreConnectUploadComponents`, `AppStoreConnectSettingsView`.
- `Editor/` — `EditorRowView` (one row: header, horizontal scroll of canvases, per-template control bars), `EditorRowHeader`, `EditorRowMenuContent`, `AddRowButton`, `AddTemplateButton`, `RowPreviewView`, `SvgPasteDialog`, `ItemProviderImageLoader` (iOS image drops/picks).
- `Canvas/` — `RowCanvasSceneView` (unified per-row canvas), `CanvasShapeView` (drag/resize/rotate, selection, hover, SVG caching, inline text edit, image/screenshot drops) split across `CanvasShapeRenderContent`, `CanvasShapeDisplayGeometry`, `CanvasShapeHandlesOverlay`, `CanvasShapeContextMenuContent`, `CanvasSelectionLayer`. Plus `ResizeHandles`, `CursorHelper`, `MiddleMousePanView`, `InlineTextEditor`, `RichTextFormatBar`, `AlignmentGuideLineView`, `CanvasTemplateSeparatorLines`, `StarShape`, `TextLayoutStyle`.
- `Inspector/` — `InspectorPanel` (row label, size presets, background editor, shape toolbar, device/border toggles), `BackgroundEditor`, `GradientAngleWheel`, `GradientCenterPicker`, `GradientStopEditor`.
- `Toolbar/` — `ShapePropertiesBar` (bottom bar) with `ShapePropertiesSingleSelectionBar` / `ShapePropertiesMultiSelectionBar` / `ShapePropertiesComponents`; `ShapeToolbar`, `ShapeFillSwatchButton`, `ShapeOutlineControls`, `ShapeDeviceShadowControls`, `ShapeDeviceModelRotationControls`, `DeviceShadowPopover`, `Device3DAppearancePopover`, `TemplateControlBar`, `BarPopover`, `FontPicker`, `ImageSourceMenu`, `ZoomControls` (min 0.50, max 2.0, step 0.25), and locale UI (`LocaleToolbarMenu`, `LocalePresetsSheet`, `LocaleTranslationOverviewSheet`, `LocaleOverrideIndicator`).
- `DeviceFrames/Rendering/` — `DeviceFrameView` (abstract bezels + real PNG frames), `DeviceFrameImageView` (image-based), `ProgrammaticDeviceFrameView` (non-image), `DeviceModelFrameView` (SceneKit 3D), `LiveDeviceModelView` (real-time 3D preview). `DeviceFrames/UI/` — `DevicePickerMenu`, `DeviceMenuContent`.

**Key patterns:**
- Colors persist via `CodableColor` (NSColor → sRGB components).
- Canvas uses a unified ZStack: all templates in a row share one canvas. Shapes span across templates; `visibleShapes(forTemplateAt:)` clips per-template.
- Display scale maps large pixel dimensions (e.g. 1242×2688) down to ~500px height for editing, adjustable via zoom.
- Option+Drag duplicates a shape (macOS); custom font import via `AppState.importCustomFont()` / `removeCustomFont()`; batch image import + device detection via `AppState.batchImportImages()`.
- Keyboard shortcuts (macOS): Cmd+C/V/X, Cmd+A select all, Cmd+D duplicate, Delete, Esc deselect, Cmd+Shift+]/[ z-order, arrows nudge (Shift ×10), Cmd+]/[ cycle locale, Cmd+Option+0 base locale, Cmd++/- zoom, Cmd+0 reset zoom, F focus selection.

## Regression Prevention

**Export/preview parity (CRITICAL):**
- Exported images must always match exactly what the editor shows. After implementing any visual feature (backgrounds, shapes, effects, layout), always verify that `ExportService.renderTemplateImage` produces the same result as the editor canvas.
- The export ZStack must use `ZStack(alignment: .topLeading)` — same as the editor — because `CanvasShapeView` uses `.position()` which is relative to the parent's coordinate origin.
- All background views in export must have explicit `.frame(width:height:)` — `GeometryReader` inside `resolvedBackgroundView` is greedy and will break layout without it.
- When views depend on container size (e.g., tiling), pass `modelSize` so rendering is consistent across editor (display-scale) and export (model-scale) contexts.
- Zoom must never affect screenshot content — use model-space dimensions for any size-dependent rendering logic.
- **Prefer scale-independent SwiftUI APIs** (e.g., `UnitPoint`, `LinearGradient` start/end points, `AngularGradient` angle) over absolute-value APIs (e.g., `RadialGradient.endRadius`). Scale-independent APIs produce identical results at any frame size, guaranteeing editor/export parity without extra work. When an absolute-value API is unavoidable, read the actual rendered frame from a **`Canvas`** (its draw `size` is available synchronously) — **not** `GeometryReader`, whose size-dependent child isn't reliably resolved before an offscreen snapshot (`NSHostingView`/`ImageRenderer`) captures, so it renders blank intermittently in export. Never derive absolute values from `modelSize`, which doesn't match the editor's display-space frame.
- When adding a new visual feature, write an export test in `ExportServiceTests` that verifies both spanning and non-spanning rendering produce valid, distinct output per template.

**Coordinate spaces — model vs display:**
- Model space = actual pixel dimensions (e.g., 1242×2688). All shape positions, sizes, and template dimensions are stored in model space.
- Display space = model space × `displayScale` (which includes zoom). The editor renders at display scale; export renders at model scale (displayScale=1.0).
- Never use display-space values for logic that affects visual output (tile counts, shape filtering, background sizing). Always derive from model-space values.
- `CanvasShapeView` multiplies by `displayScale` internally — pass `1.0` in export, the actual display scale in the editor. `ShadowConfig` geometry follows the same rule (model-space, multiplied at render).
- **`modelSize` ≠ rendered frame size in the editor.** `modelSize` is always in model space, but the editor view frame is in display space (model × displayScale × zoom). If a SwiftUI API requires absolute point values in the view's coordinate system (e.g., `RadialGradient.endRadius`), read the actual rendered size from a `Canvas` draw closure — do NOT use `modelSize`, and do NOT use `GeometryReader` in any view that gets rasterized through the export/snapshot path (it can capture blank). APIs that use relative coordinates (`UnitPoint`, angles) are safe with any frame size. This distinction is critical: using `modelSize` for absolute values causes the editor to render differently from export.

**Backward-compatible persistence:**
- All new model properties must use `decodeIfPresent` with a sensible default in the `init(from decoder:)`. Users have existing saved projects — adding a required field will crash on load.
- When renaming a stored property, use `case newName = "oldName"` in CodingKeys to keep reading old data. (Several models use short coding keys, e.g. `DeviceBodyMaterial`/`DeviceLighting` — preserve those raw values.)
- After any change to the on-disk JSON shape, regenerate `tools/project-schema.json` (skill: `gen-project-schema`).
- Test that existing project files still load after model changes.

**Image resource lifecycle:**
- Images (screenshots, backgrounds) are stored as PNG files in `projects/<uuid>/resources/` and referenced by filename strings in the model.
- When replacing a single image reference, call `cleanupUnreferencedImage()`. When removing multiple references at once (deleting a template, row, or shape), use `cleanupUnreferencedImages()` which collects all referenced filenames via `allReferencedImageFileNames()` in a single pass then removes orphans.
- `allReferencedImageFileNames()` and `isImageFileReferenced()` check all shapes, rows, templates, and locale overrides — update them when adding new image-bearing properties.
- Use `NSImage.fromSecurityScopedURL()` (in `Extensions/CodableColor.swift`) when loading images from user-picked file URLs.

**Exhaustive switch coverage:**
- `BackgroundStyle`, `ShapeType`, `ImageFillMode` (fill/fit/stretch/tile), `DeviceCategory` (iphone/ipadPro11/ipadPro13/macbook/androidPhone/pixel9/androidTablet/invisible), `GradientType` are enums used in switch statements across the codebase. Adding a new case requires updating every switch — check `EditorRowView`, `ExportService`, `BackgroundEditor`, `CanvasShapeView`, `ShapePropertiesBar`, and `InspectorPanel`.
- The `BackgroundFillable` protocol extension (`backgroundFillView`) must handle all `BackgroundStyle` cases. Both editor and export use this same code path.

**SwiftUI type-checker limits:**
- Large `@ViewBuilder` bodies cause "unable to type-check in reasonable time" errors. If a view body grows complex, extract sub-views into separate `@ViewBuilder` methods (see `EditorRowView.canvasView`, `backgroundLayer`, and the `CanvasShapeView`/`ShapePropertiesBar` splits as examples).
- Prefer `if/else` over complex ternaries in view builders.

**Spanning backgrounds:**
- `row.isSpanningBackground` controls whether a background renders once across all templates or repeats per-template. This applies to both gradient and image styles (not color).
- In the editor, spanning renders a full-width background behind the HStack of templates. In export, it renders at full row width with an offset per template.
- Per-template overrides (`template.overrideBackground`) always take priority over the row spanning background.

**Cross-platform (macOS + iPad):**
- macOS-first code uses `NSImage`/`NSColor`/`NSFont` aliased to UIKit types on iOS via `Platform/PlatformAliases.swift`. AppKit-only drawing/window/event APIs (NSEvent, NSSavePanel, NSPasteboard, NSUserUnixTask, etc.) must be guarded with `#if os(macOS)` and given an iOS branch or no-op.
- Route modifier-key reads through `PlatformModifiers` (off on iPad) rather than touching `NSEvent` directly.
- Image encoding/decoding goes through the `Platform/` shims and `ExportImageEncoder` so both platforms produce identical PNG/JPEG output.
- Image sourcing differs by platform: macOS uses drag-drop + `NSOpenPanel`; iOS routes through `ImageSourceMenu` (inline menu) or the `.imageSourcePicker(isPresented:onImage:)` modifier (confirmation dialog), both offering Photo Library / Camera / Files and normalizing EXIF orientation via `uprightNormalized()`. Prefer canonical iOS controls (`.borderedProminent` buttons, SF Symbols) over desktop drop-zone affordances on iPad.

**UI consistency (`UIMetrics`):**
- All view-layer constants — font sizes, slider widths, swatch sizes, corner radii, border widths, overlay opacities — live in `Code/Views/UIMetrics.swift`. Reach for those before hardcoding values, and add new entries there when you need a new shared constant.
- **Never use `.white` / `.black` opacities for chrome that sits over arbitrary content** (toolbars, gradients, overlays). They don't adapt to dark mode. Use `Color.primary` / `.secondary` / `.separator` with the opacities in `UIMetrics.Opacity`, or `UIMetrics.Stroke.subtle` / `.section` for hairline borders.
- Properties bar sections must use `ShapePropertiesSection` — and the parent HStack of sections must use `ShapePropertiesSectionLayout.horizontalPadding` / `.verticalPadding` so sections align flush with the bar edges.
- Toggles in compact toolbars use `.toggleStyle(.switch).controlSize(.small)`. The exception is the inspector's Visibility section, which uses `.toggleStyle(.checkbox)` because switches would break the 2-column LazyVGrid layout — keep that as is.
- `ActionButton` (default `frameSize: 22`, `iconSize: 11`) is the canonical small icon button. Match its size when adding adjacent menu/buttons that aren't `ActionButton` (e.g., the ellipsis menu in `TemplateControlBar`).
