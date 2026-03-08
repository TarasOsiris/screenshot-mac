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

No tests exist. No linter configured.

## Custom Commands

- `/gwip` — Stage all changes, commit with a WIP message summarizing changes, and push to current branch.

## Architecture

**App entry:** `screenshotApp.swift` — injects `AppState` into the SwiftUI environment via `@State` + `.environment()`.

**State management:** `AppState` (`@Observable`) is the single source of truth. All mutations (projects, rows, shapes, templates) go through AppState methods, which call `scheduleSave()` to debounce persistence (0.3s).

**Data model hierarchy:**
- `Project` → has many `ScreenshotRow` (stored in `ProjectData`)
- `ScreenshotRow` → has `templates: [ScreenshotTemplate]` (columns) + `shapes: [CanvasShapeModel]` (canvas elements)
- `CanvasShapeModel` → union type via `ShapeType` enum (rectangle, circle, text, image, device). Type-specific properties are optionals on the same struct.

**Persistence:** `PersistenceService` — JSON files in `~/Library/Application Support/screenshot/`. Project index at `projects.json`, each project's data at `projects/<uuid>/project.json`, images in `projects/<uuid>/resources/`.

**Export:** `ExportService` — renders each template to PNG using SwiftUI `ImageRenderer` at 1:1 pixel scale. Export creates a folder per project, subfolders per row (when multiple rows).

**View hierarchy:**
- `ContentView` — toolbar (project selector, zoom, export), vertical scroll of rows, inspector panel, shape properties bar
- `EditorRowView` — single row with horizontal template canvases and row controls
- `CanvasShapeView` — renders individual shapes on canvas with drag/resize handles
- `InspectorPanel` — right sidebar for row/template settings
- `ShapeToolbar` — toolbar for adding shapes to canvas
- `ShapePropertiesBar` — bottom bar for editing selected shape properties
- `DeviceFrameView` — iPhone device frame rendering

**Key patterns:**
- Colors are persisted via `CodableColor` wrapper (NSColor → sRGB components)
- Canvas uses a coordinate system where shapes span across all templates in a row; `visibleShapes(forTemplateAt:)` clips per-template
- The display scale maps large pixel dimensions (e.g., 1242x2688) down to ~500px height for editing, adjustable via zoom
