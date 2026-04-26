---
name: regression-checklist
description: Walk the project's regression-prevention checklist (export/preview parity, model-vs-display coordinates, backward-compatible persistence, exhaustive switch coverage, image lifecycle, spanning backgrounds, dark mode, rotated elements, image-based frames, clipped mode) against a pending diff before committing visual or model changes. Use after editing anything in Views/, Services/ExportService.swift, Models/, or BackgroundFillable, and before shipping.
---

# Regression Checklist

Run this skill before committing any change that touches visual rendering or the persistent data model. It is a structured walk-through of the "Regression Prevention" section of `CLAUDE.md`.

## Inputs

- The pending diff: `git diff` plus staged changes.
- The list of touched files.

If the diff is empty in the relevant directories, say so and stop.

## Phase 1 — Classify the change

Decide which bucket the change falls into. Multiple may apply.

| Bucket | Triggers if diff touches… |
|---|---|
| Visual rendering | `Views/Canvas/**`, `Views/Inspector/**`, `Views/Toolbar/**`, `BackgroundFillable`, `BackgroundEditor`, `EditorRowView`, `RowCanvasSceneView`, `CanvasShapeView` |
| Export | `Services/ExportService.swift`, `Views/Export/**`, `ExportFolderService` |
| Model | `Models/**`, anything `Codable` |
| Device frames | `DeviceFrames/**`, `DeviceFrameView`, `DeviceModelFrameView`, `ProgrammaticDeviceFrameView` |
| Locale | `Models/LocaleModels.swift`, `LocaleService`, `LocaleToolbarMenu`, `Localizable.xcstrings` |
| Persistence | `Services/PersistenceService.swift`, `AppState+Persistence.swift`, `ICloudSyncService`, `ICloudMonitor` |

## Phase 2 — Run the checks

For each bucket the diff hit, run the matching checks below. For each check, output ✅ / ⚠️ / 🔴 with `file:line` evidence.

### Visual rendering
1. Editor and export render the same way (`ExportService.renderTemplateImage` covers the new path).
2. Export `ZStack` uses `alignment: .topLeading`.
3. New background views inside `resolvedBackgroundView` have explicit `.frame(width:height:)`.
4. No absolute-value SwiftUI APIs derived from `modelSize` (must use `GeometryReader` or scale-independent APIs).
5. Verified across: light + dark mode, image-based frames, clipped mode, rotated elements.
6. Zoom does not affect screenshot content (model-space dimensions used for size-dependent logic).

### Export
1. Spanning backgrounds render once across all templates with correct per-template offset.
2. Per-template `template.overrideBackground` still wins over row spanning.
3. Export passes `displayScale: 1.0` to `CanvasShapeView`.
4. New visual feature has a corresponding test in `ExportServiceTests` covering both spanning and non-spanning, with distinct output per template.

### Model
1. Every new `Codable` property uses `decodeIfPresent` with a sensible default in `init(from decoder:)`.
2. Renamed properties keep `case newName = "oldName"` in `CodingKeys`.
3. New enum cases (`BackgroundStyle`, `ShapeType`, `ImageFillMode`, `DeviceCategory`, `GradientType`) are handled in every switch site — grep for the enum name and verify each match.
4. New image-bearing properties are reflected in `allReferencedImageFileNames()` and `isImageFileReferenced()`.
5. If schema-affecting: run the `gen-project-schema` skill afterward.

### Device frames
1. Image-based frames AND programmatic frames both work.
2. Per-color variants for affected frames render correctly.
3. Landscape orientations covered if the frame supports them.
4. Screen insets and corner radii match `DeviceFrameImageSpec`.

### Locale
1. New text-bearing shape properties have a corresponding `ShapeLocaleOverride` field, and `LocaleService.splitUpdate()` knows about them.
2. Base locale (first in list) renders correctly; non-base locales fall back to base when override is empty.
3. New user-facing strings use `String(localized:)` (run the `add-localized-string` skill if not).

### Persistence
1. Existing project files still load — round-trip test in `AppStateTests` if shape changed.
2. iCloud merge logic (`Project.merged(with:)`) handles the new field idempotently.
3. Tombstone fields (`isDeleted`, `deletedAt`) are not accidentally cleared.

## Phase 3 — Verify

Run the build (and tests if model changes were involved):

```
xcodebuild -scheme screenshot -destination 'platform=macOS' build 2>&1 | tail -20
```

For model changes:

```
killall screenshot 2>/dev/null; xcodebuild -scheme screenshot -destination 'platform=macOS' test 2>&1 | tail -50
```

## Output

```
## Regression Checklist Result

Buckets hit: <list>
Files reviewed: <count>

### 🔴 Must fix before commit
- <bucket> · <file:line> — <problem>

### ⚠️ Verify manually
- <bucket> · <what to click through in the running app>

### ✅ Passed
- <bucket> · <one line>
```

Cite `file:line` for every finding. Skip categories with no relevant changes.
