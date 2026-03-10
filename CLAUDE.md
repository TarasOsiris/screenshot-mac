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

UI tests exist (`screenshotUITests` scheme) but no unit tests. No linter configured.

## Custom Commands

- `/gwip` — Stage all changes, commit with a WIP message summarizing changes, and push to current branch.
- `/ship [version]` — Bump build number (and optionally marketing version), build, and upload to App Store Connect.

## Architecture

**App entry:** `screenshotApp.swift` — injects `AppState` into the SwiftUI environment via `@State` + `.environment()`. Defines keyboard shortcuts and menu items (Edit, View, Locale menus).

**State management:** `AppState` (`@Observable`) is the single source of truth. All mutations (projects, rows, shapes, templates, locales) go through AppState methods, which call `scheduleSave()` to debounce persistence (0.3s). Undo/redo via macOS `UndoManager`.

**Data model hierarchy:**
- `Project` → has many `ScreenshotRow` (stored in `ProjectData`)
- `ScreenshotRow` → has `templates: [ScreenshotTemplate]` (columns) + `shapes: [CanvasShapeModel]` (canvas elements). Implements `BackgroundFillable`.
- `ScreenshotTemplate` → per-column background/gradient settings. Implements `BackgroundFillable`.
- `CanvasShapeModel` → union type via `ShapeType` enum (rectangle, circle, text, image, device, svg). Type-specific properties are optionals on the same struct.
- `BackgroundStyle` → enum (color, gradient) with `GradientConfig` (color stops, angle, 12 presets).
- `LocaleState` → locale definitions + active locale + per-shape overrides (`ShapeLocaleOverride` for text properties).

**Services:**
- `PersistenceService` — JSON files in `~/Library/Application Support/screenshot/`. Project index at `projects.json`, each project's data at `projects/<uuid>/project.json`, images in `projects/<uuid>/resources/`. Supports `SCREENSHOT_DATA_DIR` env override for tests.
- `ExportService` — renders templates to PNG/JPEG via SwiftUI `ImageRenderer` at configurable scale (1x–3x). Multi-locale export creates locale subfolders; multi-row creates row label subfolders.
- `LocaleService` — resolves shapes with locale overrides. `splitUpdate()` separates base shape mutations from locale-specific text properties. Base locale is first in list; non-base locales get text-only overrides.
- `AlignmentService` — snap-to-grid alignment. Computes snaps from dragged shape against other shapes and template boundaries (4px threshold). Returns snap deltas and guide lines.

**View hierarchy:**
- `ContentView` — toolbar (project selector, zoom, locale menu, export), vertical scroll of rows, shape properties bar (bottom), inspector panel (right sidebar)
- `EditorRowView` — single row with header controls, horizontal scroll of template canvases, per-template control bars
- `CanvasShapeView` — renders individual shapes with drag/resize/rotate, selection overlay, hover state; handles SVG caching, inline text editing, image/screenshot drops
- `LocaleBanner` — top contextual banner when editing a non-base locale
- `InspectorPanel` — right sidebar: row label, screenshot size presets, background editor, shape toolbar, device/border toggles
- `BackgroundEditor` — background style picker, gradient preset picker, gradient stop editor, angle wheel
- `ShapeToolbar` — grid of 6 shape type buttons (Rectangle, Circle, Text, Image, Device, SVG)
- `ShapePropertiesBar` — bottom bar: color, opacity, rotation, size, position, border radius, text properties, image/device properties
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
