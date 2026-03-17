# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Screenshot Bro — macOS app for generating App Store & Google Play screenshots with device frames, shapes, and a multi-row editor. Pure Swift + SwiftUI, no external dependencies.

## UX Reference

Sketch is the main reference project. UX patterns (cursors, handles, interactions, inspector behavior, etc.) should follow Sketch conventions when applicable.

## Build

```
xcodebuild -scheme screenshot -destination 'platform=macOS' build
```

Run unit tests:
```
xcodebuild -scheme screenshot -destination 'platform=macOS' test
```

Unit tests cover `AppState` operations and `ExportService` rendering (`screenshotTests/`). UI tests exist (`screenshotUITests` scheme). No linter configured.

## Custom Commands

- `/gwip` — Stage all changes, commit with a WIP message summarizing changes, and push to current branch.
- `/ship [version]` — Bump build number (and optionally marketing version), build, and upload to App Store Connect.

## Architecture

**App entry:** `screenshotApp.swift` — injects `AppState` into the SwiftUI environment via `@State` + `.environment()`. Defines keyboard shortcuts and menu items (Edit, View, Locale menus).

**State management:** `AppState` (`@Observable`) is the single source of truth. All mutations (projects, rows, shapes, screenshot columns, locales) go through AppState methods, which call `scheduleSave()` to debounce persistence (0.3s). Undo/redo via macOS `UndoManager`.

**Data model hierarchy:**
- `Project` → has many `ScreenshotRow` (stored in `ProjectData`)
- `ScreenshotRow` → has `templates: [ScreenshotTemplate]` (columns) + `shapes: [CanvasShapeModel]` (canvas elements). Implements `BackgroundFillable`.
- `ScreenshotTemplate` → per-column background/gradient settings. Implements `BackgroundFillable`.
- `CanvasShapeModel` → union type via `ShapeType` enum (rectangle, circle, star, text, image, device, svg). Type-specific properties are optionals on the same struct.
- `BackgroundStyle` → enum (color, gradient, image) with `GradientConfig` (color stops, angle, type, center) and `BackgroundImageConfig` (fileName, fillMode, opacity). `BackgroundFillable` protocol provides `backgroundFillView(image:modelSize:)` and `resolvedBackgroundView(screenshotImages:modelSize:)` for rendering.
- `GradientType` → enum (linear, radial, angular). Linear uses `LinearGradient` with angle-derived start/end points. Radial uses `RadialGradient` inside a `GeometryReader` for size-aware `endRadius`. Angular uses `AngularGradient` with center and angle offset.
- `LocaleState` → locale definitions + active locale + per-shape overrides (`ShapeLocaleOverride` for text properties).

**Services:**
- `PersistenceService` — JSON files in `~/Library/Application Support/screenshot/`. Project index at `projects.json`, each project's data at `projects/<uuid>/project.json`, images in `projects/<uuid>/resources/`. Supports `SCREENSHOT_DATA_DIR` env override for tests.
- `ExportService` — renders templates to PNG/JPEG via SwiftUI `ImageRenderer` at configurable scale (1x–3x). Multi-locale export creates locale subfolders; multi-row creates row label subfolders.
- `LocaleService` — resolves shapes with locale overrides. `splitUpdate()` separates base shape mutations from locale-specific text properties. Base locale is first in list; non-base locales get text-only overrides.
- `AlignmentService` — snap-to-grid alignment. Computes snaps from dragged shape against other shapes and template boundaries (4px threshold). Returns snap deltas and guide lines.

**View hierarchy:**
- `ContentView` — toolbar (project selector, zoom, locale menu, export), vertical scroll of rows, shape properties bar (bottom), inspector panel (right sidebar)
- `EditorRowView` — single row with header controls, horizontal scroll of template canvases, per-template control bars
- `CanvasShapeView` — renders individual shapes with drag/resize/rotate, selection overlay, hover state; handles SVG caching (debounced during resize), inline text editing, image/screenshot drops
- `LocaleBanner` — top contextual banner when editing a non-base locale
- `InspectorPanel` — right sidebar: row label, screenshot size presets, background editor, shape toolbar, device/border toggles
- `BackgroundEditor` — background style picker, gradient preset picker, gradient stop editor, angle wheel
- `ShapeToolbar` — grid of 6 shape type buttons (Rectangle, Circle, Text, Image, Device, SVG)
- `ShapePropertiesBar` — bottom bar: color, opacity, rotation, border radius, text properties, image/device properties, outline, clip. All toggles use `.toggleStyle(.switch)` with `.controlSize(.small)`. Sections use a shared `section()` helper with consistent min height.
- `TemplateControlBar` — per-template controls: background color/style/gradient, device screenshot, export preview
- `DeviceFrameView` — iPhone device frame rendering with accurate bezel/screen/button specs
- `InlineTextEditor` — NSViewRepresentable for text editing with centering
- `AlignmentGuideLineView` — renders blue snap guide lines
- `LocaleToolbarMenu` — locale management: add/remove/reorder locales, translation progress
- `ZoomControls` — zoom slider with min 0.75, max 2.0, step 0.25
- `SvgPasteDialog` — sheet for pasting SVG content with dimensions
- `SettingsView` — General tab (appearance, defaults) and Export tab (format, scale)

**Key patterns:**
- Colors are persisted via `CodableColor` wrapper (NSColor → sRGB components)
- Canvas uses a unified ZStack: all templates in a row share one canvas. Shapes span across templates; `visibleShapes(forTemplateAt:)` clips per-template
- The display scale maps large pixel dimensions (e.g., 1242×2688) down to ~500px height for editing, adjustable via zoom
- Option+Drag creates duplicate shape
- Keyboard shortcuts: Cmd+C/V/X copy/paste/cut, Cmd+D duplicate, Delete delete, Esc deselect, Cmd+Shift+]/[ z-order, arrow keys nudge (Shift ×10), Cmd+E export, Cmd+Shift+R add row, Cmd+]/[ cycle locale

## Regression Prevention

**Export/preview parity (CRITICAL):**
- Exported images must always match exactly what the editor shows. After implementing any visual feature (backgrounds, shapes, effects, layout), always verify that `ExportService.renderTemplateImage` produces the same result as the editor canvas.
- The export ZStack must use `ZStack(alignment: .topLeading)` — same as the editor — because `CanvasShapeView` uses `.position()` which is relative to the parent's coordinate origin.
- All background views in export must have explicit `.frame(width:height:)` — `GeometryReader` inside `resolvedBackgroundView` is greedy and will break layout without it.
- When views depend on container size (e.g., tiling), pass `modelSize` so rendering is consistent across editor (display-scale) and export (model-scale) contexts.
- Zoom must never affect screenshot content — use model-space dimensions for any size-dependent rendering logic.
- **Prefer scale-independent SwiftUI APIs** (e.g., `UnitPoint`, `LinearGradient` start/end points, `AngularGradient` angle) over absolute-value APIs (e.g., `RadialGradient.endRadius`). Scale-independent APIs produce identical results at any frame size, guaranteeing editor/export parity without extra work. When an absolute-value API is unavoidable, use `GeometryReader` to read the actual rendered frame — never derive absolute values from `modelSize`, which doesn't match the editor's display-space frame.
- When adding a new visual feature, write an export test in `ExportServiceTests` that verifies both spanning and non-spanning rendering produce valid, distinct output per template.

**Coordinate spaces — model vs display:**
- Model space = actual pixel dimensions (e.g., 1242×2688). All shape positions, sizes, and template dimensions are stored in model space.
- Display space = model space × `displayScale` (which includes zoom). The editor renders at display scale; export renders at model scale (displayScale=1.0).
- Never use display-space values for logic that affects visual output (tile counts, shape filtering, background sizing). Always derive from model-space values.
- `CanvasShapeView` multiplies by `displayScale` internally — pass `1.0` in export, the actual display scale in the editor.
- **`modelSize` ≠ rendered frame size in the editor.** `modelSize` is always in model space, but the editor view frame is in display space (model × displayScale × zoom). If a SwiftUI API requires absolute point values in the view's coordinate system (e.g., `RadialGradient.endRadius`), you MUST use `GeometryReader` to read the actual rendered size — do NOT use `modelSize`. APIs that use relative coordinates (`UnitPoint`, angles) are safe with any frame size. This distinction is critical: using `modelSize` for absolute values causes the editor to render differently from export.

**Backward-compatible persistence:**
- All new model properties must use `decodeIfPresent` with a sensible default in the `init(from decoder:)`. Users have existing saved projects — adding a required field will crash on load.
- When renaming a stored property, use `case newName = "oldName"` in CodingKeys to keep reading old data.
- Test that existing project files still load after model changes.

**Image resource lifecycle:**
- Images (screenshots, backgrounds) are stored as PNG files in `projects/<uuid>/resources/` and referenced by filename strings in the model.
- When replacing a single image reference, call `cleanupUnreferencedImage()`. When removing multiple references at once (deleting a template, row, or shape), use `cleanupUnreferencedImages()` which collects all referenced filenames via `allReferencedImageFileNames()` in a single pass then removes orphans.
- `allReferencedImageFileNames()` and `isImageFileReferenced()` check all shapes, rows, templates, and locale overrides — update them when adding new image-bearing properties.
- Use `NSImage.fromSecurityScopedURL()` (in `Extensions/CodableColor.swift`) when loading images from user-picked file URLs.

**Exhaustive switch coverage:**
- `BackgroundStyle`, `ShapeType`, `ImageFillMode`, `DeviceCategory`, `GradientType` are enums used in switch statements across the codebase. Adding a new case requires updating every switch — check `EditorRowView`, `ExportService`, `BackgroundEditor`, `CanvasShapeView`, `ShapePropertiesBar`, and `InspectorPanel`.
- The `BackgroundFillable` protocol extension (`backgroundFillView`) must handle all `BackgroundStyle` cases. Both editor and export use this same code path.

**SwiftUI type-checker limits:**
- Large `@ViewBuilder` bodies cause "unable to type-check in reasonable time" errors. If a view body grows complex, extract sub-views into separate `@ViewBuilder` methods (see `EditorRowView.canvasView`, `backgroundLayer` as examples).
- Prefer `if/else` over complex ternaries in view builders.

**Spanning backgrounds:**
- `row.isSpanningBackground` controls whether a background renders once across all templates or repeats per-template. This applies to both gradient and image styles (not color).
- In the editor, spanning renders a full-width background behind the HStack of templates. In export, it renders at full row width with an offset per template.
- Per-template overrides (`template.overrideBackground`) always take priority over the row spanning background.
