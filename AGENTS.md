# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Overview

Screenshot Bro — macOS app for generating App Store & Google Play screenshots with device frames, shapes, and a multi-row editor. Pure Swift + SwiftUI, no external dependencies.

## Build

```
xcodebuild -scheme screenshot -destination 'platform=macOS' build
```

No tests exist. No linter configured.

## Custom Commands

- `/gwip` — Stage all changes, commit with a WIP message summarizing changes, and push to current branch.

## Architecture

**App entry:** `screenshotApp.swift` — injects `AppState` into the SwiftUI environment via `@State` + `.environment()`, and defines app-level edit commands (duplicate/delete/deselect/reorder + zoom shortcuts).

**State management:** `AppState` (`@Observable`) is the source of truth for projects, rows, selection, and cached images. Data mutations call `scheduleSave()` (0.3s debounce). Undo snapshots row state and normalizes selection on undo/redo.

**Data model hierarchy:**
- `Project` → has many `ScreenshotRow` (stored in `ProjectData`)
- `ScreenshotRow` → has `templates: [ScreenshotTemplate]` (columns) + `shapes: [CanvasShapeModel]` (canvas elements)
- `CanvasShapeModel` → union type via `ShapeType` enum (`rectangle`, `circle`, `text`, `image`, `device`, `svg`). Type-specific properties are optionals on the same struct.

**Persistence:** `PersistenceService` — JSON files in `~/Library/Application Support/screenshot/`. Project index at `projects.json`, each project's data at `projects/<uuid>/project.json`, image resources in `projects/<uuid>/resources/`.

**Export:** `ExportService` renders each template to PNG via SwiftUI `ImageRenderer` at 1:1 scale. Export creates a root folder per project, and subfolders per row when exporting multiple rows. `ContentView` can auto-open the exported folder in Finder when export completes (`openExportFolderOnSuccess` setting).

**View hierarchy:**
- `ContentView` — toolbar (project selector, zoom, export), vertical scroll of rows, inspector panel, shape properties bar
- `EditorRowView` — single row with horizontal template canvases and row controls
- `CanvasShapeView` — renders individual shapes with drag/resize/rotation behavior, inline text editing, and image drop/import for image/device shapes
- `InspectorPanel` — right sidebar for row/template settings
- `GradientStopEditor` + `GradientAngleWheel` — gradient stop editing and angle control in inspector
- `ShapeToolbar` — toolbar for adding shapes to canvas
- `ShapePropertiesBar` — bottom bar for editing selected shape properties
- `DeviceFrameView` — iPhone device frame rendering

**Key patterns:**
- Colors are persisted via `CodableColor` wrapper (NSColor → sRGB components)
- Canvas uses a coordinate system where shapes span across all templates in a row; `visibleShapes(forTemplateAt:)` clips per-template
- Selection APIs are centralized in `AppState` (`selectRow`, `selectShape`, `deselectAll`) to keep row/shape focus consistent
- Row canvas dragging uses `AlignmentService` and `AlignmentGuideLineView` for snap guides
- Image handling uses `saveImage(_:for:)`; device and image shapes persist file names and share `screenshotImages` cache
- The display scale maps large pixel dimensions (e.g., 1242x2688) down to ~500px height for editing, adjustable via zoom

## Settings

`SettingsView` uses `@AppStorage` keys:
- `defaultScreenshotSize`
- `defaultTemplateCount`
- `defaultZoomLevel`
- `exportFormat` (currently stored only)
- `exportScale` (currently stored only)
- `openExportFolderOnSuccess`
