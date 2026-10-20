#if os(macOS)
import Foundation
import MCP

enum MCPToolName: String, CaseIterable {
    case listTemplates = "list_templates"
    case listProjects = "list_projects"
    case getProject = "get_project"
    case createProject = "create_project"
    case renameProject = "rename_project"
    case deleteProject = "delete_project"
    case switchProject = "switch_project"
    case addRow = "add_row"
    case updateRow = "update_row"
    case moveRow = "move_row"
    case deleteRow = "delete_row"
    case addTemplate = "add_template"
    case removeTemplate = "remove_template"
    case addShape = "add_shape"
    case updateShape = "update_shape"
    case deleteShape = "delete_shape"
    case importScreenshots = "import_screenshots"
    case addLocale = "add_locale"
    case removeLocale = "remove_locale"
    case setTranslation = "set_translation"
    case exportProject = "export_project"
    case renderPreview = "render_preview"
    case getAppStoreMetadata = "get_app_store_metadata"
    case updateAppStoreDescription = "update_app_store_description"
    case previewAppStoreScreenshotSync = "preview_app_store_screenshot_sync"
    case applyAppStoreScreenshotSync = "apply_app_store_screenshot_sync"
    case getSyncJobStatus = "get_sync_job_status"
    case cancelSyncJob = "cancel_sync_job"
    case listVariants = "list_variants"
    case createVariant = "create_variant"
    case setRowVariant = "set_row_variant"
    case deleteVariant = "delete_variant"
    case batch = "batch"
    case setTranslations = "set_translations"
    case listCatalog = "list_catalog"
    case undo = "undo"
    case redo = "redo"
    case updateTemplate = "update_template"
    case duplicateShape = "duplicate_shape"
    case duplicateRow = "duplicate_row"
    case duplicateTemplate = "duplicate_template"
    case moveTemplate = "move_template"
    case replaceImage = "replace_image"
    case setAllDevices = "set_all_devices"
    case arrangeShapes = "arrange_shapes"
    case setBaseLocale = "set_base_locale"
    case setLocaleLayout = "set_locale_layout"
    case updateAppStoreMetadata = "update_app_store_metadata"
    case listAppStoreApps = "list_app_store_apps"
    case linkProjectStores = "link_project_stores"
    case previewPlayUpload = "preview_play_upload"
    case uploadPlayScreenshots = "upload_play_screenshots"

    nonisolated static var available: [MCPToolName] { allCases.filter(\.isAvailable) }

    /// Tools behind a feature flag: listed and dispatched only while it is on.
    nonisolated var isAvailable: Bool {
        switch self {
        case .listVariants, .createVariant, .setRowVariant, .deleteVariant: FeatureFlags.abTesting
        default: true
        }
    }

    /// Hints for clients deciding what to confirm. Anything that overwrites or removes is
    /// destructive; only App Store Connect reaches outside the app.
    nonisolated var annotations: Tool.Annotations {
        switch self {
        case .listTemplates, .listProjects, .getProject, .renderPreview, .getSyncJobStatus, .listVariants, .listCatalog:
            Tool.Annotations(readOnlyHint: true, openWorldHint: false)
        case .getAppStoreMetadata, .previewAppStoreScreenshotSync, .listAppStoreApps, .previewPlayUpload:
            Tool.Annotations(readOnlyHint: true, openWorldHint: true)
        case .applyAppStoreScreenshotSync, .updateAppStoreDescription, .updateAppStoreMetadata, .uploadPlayScreenshots:
            Tool.Annotations(readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: true)
        case .cancelSyncJob:
            Tool.Annotations(readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: true)
        case .updateRow, .updateShape, .setTranslation, .setTranslations, .renameProject, .setRowVariant,
             .updateTemplate, .setAllDevices, .arrangeShapes, .setLocaleLayout, .setBaseLocale:
            Tool.Annotations(readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false)
        case .deleteProject, .deleteRow, .deleteShape, .removeTemplate, .removeLocale, .deleteVariant,
             .importScreenshots, .moveRow, .batch, .undo, .redo, .replaceImage, .moveTemplate:
            Tool.Annotations(readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: false)
        case .switchProject, .linkProjectStores:
            Tool.Annotations(readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false)
        case .createProject, .addRow, .addTemplate, .addShape, .addLocale, .createVariant, .exportProject,
             .duplicateShape, .duplicateRow, .duplicateTemplate:
            Tool.Annotations(readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false)
        }
    }
}

nonisolated enum MCPToolCatalog {
    static let deviceCategories = DeviceCategory.allCases.map(\.rawValue)
    /// Agents read the category enum as the list of supported devices; it is only the generic fallback.
    static let deviceCategoryNote = "a generic frame, not the list of supported devices — specific models "
        + "(iPhone Duo, iPhone 17 Pro, Pixel, …) are chosen with device_frame_id"
    static let deviceFrameIdNote = "list_catalog kind device_frames lists them; pass size to get the frames built for a screenshot size"

    /// One authoritative phrasing for the tool description and the load-failure error — divergent
    /// copies contradicted each other about whether "temp" is readable (system /tmp is not; the
    /// app's own container temp is).
    static let screenshotStagingHint = "The app is sandboxed: it can read its own container and "
        + "user-granted folders, but not arbitrary paths (system /tmp and agent scratch dirs "
        + "included). If a load fails, copy the images into the app's own temp folder "
        + "\(FileManager.default.temporaryDirectory.path) and retry with those paths."

    /// Editing tools act on the project the app has open unless told otherwise; naming it makes a
    /// script independent of the window, and lets it edit a project that isn't open at all.
    private static let projectIdSchema = MCPSchema.string(
        "Project UUID to edit — from list_projects. Recommended; defaults to the project open in the app. A project that isn't open is edited and saved directly (not undoable in the app)"
    )

    private static let gradientSchema = MCPSchema.object([
        "type": MCPSchema.string("Gradient type", oneOf: ["linear", "radial", "angular"]),
        "angle": MCPSchema.number("Angle in degrees (default 135)"),
        "center_x": MCPSchema.number("Center X 0-1 for radial/angular (default 0.5)"),
        "center_y": MCPSchema.number("Center Y 0-1 for radial/angular (default 0.5)"),
        "stops": MCPSchema.array(
            of: MCPSchema.object([
                "color": MCPSchema.string("Stop color as #RRGGBB or #RRGGBBAA"),
                "location": MCPSchema.number("Stop position 0-1"),
            ], required: ["color", "location"]),
            "Color stops, at least 2"
        ),
    ], required: ["stops"])

    private static let textRunsSchema = MCPSchema.array(
        of: MCPSchema.object([
            "text": MCPSchema.string("This span's characters"),
            "color": MCPSchema.string("Span color as #RRGGBB or #RRGGBBAA (default: the shape's color)"),
            "font_weight": MCPSchema.integer("Font weight 100-900 (default: the shape's)"),
            "font_size": MCPSchema.number("Font size (default: the shape's)"),
            "font_name": MCPSchema.string("Font family, or \"system\" for the system font (default: the shape's)"),
            "italic": MCPSchema.boolean("Italic (default: the shape's)"),
            "underline": MCPSchema.boolean("Underline"),
            "strikethrough": MCPSchema.boolean("Strikethrough"),
        ], required: ["text"]),
        "Formatted text as styled spans, concatenated in order; replaces the text and all per-range formatting. Read the current spans from get_project's text_runs and send them back edited (e.g. change one word's color). Mutually exclusive with text."
    )

    private static let shadowSchema = MCPSchema.object([
        "color": MCPSchema.string("Shadow color as #RRGGBB (default black)"),
        "opacity": MCPSchema.number("0-1 (default 0.3)"),
        "radius": MCPSchema.number("Blur radius in model pixels, 0-150 (default 40)"),
        "offset_x": MCPSchema.number("Horizontal offset, -100-100 (default 0)"),
        "offset_y": MCPSchema.number("Vertical offset, -100-100 (default 30)"),
    ], description: "Drop shadow; null removes it")

    private static let textBackgroundSchema = MCPSchema.object([
        "color": MCPSchema.string("Plate color as #RRGGBB or #RRGGBBAA (default black)"),
        "opacity": MCPSchema.number("0-1"),
        "radius": MCPSchema.number("Corner radius"),
        "padding": MCPSchema.number("Padding around the text"),
        "outline_color": MCPSchema.string("Plate outline color"),
        "outline_width": MCPSchema.number("Plate outline width (0 removes it)"),
    ], description: "Rounded plate behind text; null removes it")

    private static let playUploadProperties: [String: Value] = [
        "project_id": MCPSchema.string("Project UUID — from list_projects"),
        "package_name": MCPSchema.string("Google Play application id (default: the package linked to the project)"),
        "row_ids": MCPSchema.array(of: MCPSchema.string("Row UUID"), "Original rows to upload (default: every row that isn't App Store-only)"),
        "locale_codes": MCPSchema.array(of: MCPSchema.string("Project locale code"), "Project locales to upload (default: those Play lists)"),
        "image_type": MCPSchema.string("Play image type for every included row (default: detected from each row's size)", oneOf: GPImageType.allCases.map(\.rawValue)),
    ]

    /// Background fields update_row and update_template both accept.
    private static let backgroundProperties: [String: Value] = [
        "background_color": MCPSchema.string("Solid background color as #RRGGBB; switches the background to color"),
        "background_gradient": gradientSchema,
        "background_image_path": MCPSchema.string("Absolute path of a background image; switches the background to image. \(screenshotStagingHint)"),
        "background_image_locale": MCPSchema.string("Locale the background image is for (default: the base, which every language without its own falls back to)"),
        "background_fill_mode": MCPSchema.string("How the background image fills the area", oneOf: ImageFillMode.allCases.map(\.rawValue)),
        "background_image_opacity": MCPSchema.number("Background image opacity 0-1"),
        "background_blur": MCPSchema.number("Background blur radius in model pixels (0 = none)"),
    ]

    /// Fields add_shape and update_shape both accept.
    private static let shapeProperties: [String: Value] = [
        "x": MCPSchema.number("Left edge in model pixels"),
        "y": MCPSchema.number("Top edge in model pixels"),
        "width": MCPSchema.number("Width in model pixels"),
        "height": MCPSchema.number("Height in model pixels"),
        "rotation": MCPSchema.number("Rotation in degrees"),
        "opacity": MCPSchema.number("Opacity 0-1"),
        "border_radius": MCPSchema.number("Corner radius (rectangles, invisible device frames)"),
        "color": MCPSchema.string("Fill/text color as #RRGGBB or #RRGGBBAA"),
        "text": MCPSchema.string("Text content (base locale)"),
        "text_runs": textRunsSchema,
        "clear_text_formatting": MCPSchema.boolean("Drop per-range formatting, in the base text and every translation, so the whole text uses the shape's own style"),
        "font_size": MCPSchema.number("Font size"),
        "font_name": MCPSchema.string("Font family name — list_catalog kind fonts"),
        "font_weight": MCPSchema.integer("Font weight 100-900"),
        "italic": MCPSchema.boolean("Italic text"),
        "uppercase": MCPSchema.boolean("Render the text in capitals"),
        "text_align": MCPSchema.string("Horizontal text alignment", oneOf: ["left", "center", "right"]),
        "vertical_align": MCPSchema.string("Vertical text alignment in the box", oneOf: ["top", "center", "bottom"]),
        "letter_spacing": MCPSchema.number("Letter spacing"),
        "line_height": MCPSchema.number("Line height as a multiple of the font's natural line height, 0.5-2.0 (1 = default)"),
        "line_spacing": MCPSchema.number("Legacy: extra points between lines, converted to line_height. Prefer line_height"),
        "outline_color": MCPSchema.string("Outline color as #RRGGBB"),
        "outline_width": MCPSchema.number("Outline width (0 removes the outline)"),
        "shadow": shadowSchema,
        "text_background": textBackgroundSchema,
        "device_category": MCPSchema.string("Device category (device shapes): \(deviceCategoryNote)", oneOf: deviceCategories),
        "device_frame_id": MCPSchema.string("Device frame id (device shapes) — \(deviceFrameIdNote); also sets the matching category and aspect ratio"),
        "star_points": MCPSchema.integer("Number of points (star shapes)"),
        "clip_to_template": MCPSchema.boolean("Clip the shape to its template column"),
        "fill_style": MCPSchema.string("Fill style for rectangles, circles, stars and text", oneOf: ["color", "gradient"]),
        "fill_gradient": gradientSchema,
        "shrink_to_fit": MCPSchema.boolean("Shrink text so every line fits the box in every locale (text shapes)"),
        "locked": MCPSchema.boolean("Lock the shape against canvas interaction"),
    ]

    private static let translationProperties: [String: Value] = [
        "shape_id": MCPSchema.string("Text shape UUID"),
        "locale_code": MCPSchema.string("Target locale code (must exist in the project)"),
        "text": MCPSchema.string("Translated text"),
        "text_runs": textRunsSchema,
        "auto_fit": MCPSchema.boolean("Fit overflowing text automatically (default true); false leaves the box and font untouched"),
    ]

    static var tools: [Tool] {
        allTools.compactMap { tool in
            guard let name = MCPToolName(rawValue: tool.name), name.isAvailable else { return nil }
            var annotated = tool
            annotated.annotations = name.annotations
            return annotated
        }
    }

    private static let schemasByName: [String: Value] = Dictionary(
        uniqueKeysWithValues: allTools.map { ($0.name, $0.inputSchema) }
    )

    static func inputSchema(for tool: MCPToolName) -> Value? {
        schemasByName[tool.rawValue]
    }

    /// A tool without a schema would skip argument validation entirely, so it is an error.
    static func requireInputSchema(for tool: MCPToolName) throws -> Value {
        guard let schema = inputSchema(for: tool) else {
            throw MCPToolError.failed("\(tool.rawValue) has no input schema")
        }
        return schema
    }

    private static let allTools: [Tool] = [
        Tool(
            name: MCPToolName.listTemplates.rawValue,
            description: "List bundled starter templates that create_project can instantiate.",
            inputSchema: MCPSchema.object([:])
        ),
        Tool(
            name: MCPToolName.listProjects.rawValue,
            description: "List all projects with their ids, names, and which one is active.",
            inputSchema: MCPSchema.object([:])
        ),
        Tool(
            name: MCPToolName.getProject.rawValue,
            description: "Full structured snapshot of a project: rows, template columns, shapes, locales — including every id needed by other tools. All coordinates/sizes are in model space (pixels of the target screenshot). Works on any project, open in the app window or not.",
            inputSchema: MCPSchema.object([
                "project_id": MCPSchema.string("Project UUID — from list_projects"),
                "row_ids": MCPSchema.array(of: MCPSchema.string("Row UUID"), "Only these rows (default: all)"),
                "include_translations": MCPSchema.boolean("Include per-locale text, text runs and image overrides (default true); false keeps large multilingual projects small"),
            ], required: ["project_id"])
        ),
        Tool(
            name: MCPToolName.createProject.rawValue,
            description: "Create a new project and switch to it. Pass template_id (from list_templates) to instantiate a bundled template, or rows to configure a blank project.",
            inputSchema: MCPSchema.object([
                "name": MCPSchema.string("Project name"),
                "template_id": MCPSchema.string("Bundled template id from list_templates; omit for a blank project"),
                "rows": MCPSchema.array(
                    of: MCPSchema.object([
                        "label": MCPSchema.string("Row label"),
                        "size": MCPSchema.string("Screenshot size like \"1242x2688\" (width x height in pixels)"),
                        "template_count": MCPSchema.integer("Number of screenshot columns (default 3)"),
                        "device_category": MCPSchema.string("Default device frame category: \(deviceCategoryNote)", oneOf: deviceCategories),
                        "device_frame_id": MCPSchema.string("Specific device frame id (optional) — \(deviceFrameIdNote)"),
                    ]),
                    "Row configurations for a blank project (ignored when template_id is set)"
                ),
            ], required: ["name"])
        ),
        Tool(
            name: MCPToolName.renameProject.rawValue,
            description: "Rename a project.",
            inputSchema: MCPSchema.object([
                "project_id": MCPSchema.string("Project UUID"),
                "name": MCPSchema.string("New name"),
            ], required: ["project_id", "name"])
        ),
        Tool(
            name: MCPToolName.deleteProject.rawValue,
            description: "Permanently delete a project and its files. This cannot be undone.",
            inputSchema: MCPSchema.object([
                "project_id": MCPSchema.string("Project UUID"),
            ], required: ["project_id"])
        ),
        Tool(
            name: MCPToolName.switchProject.rawValue,
            description: "Make a project the active one for editing.",
            inputSchema: MCPSchema.object([
                "project_id": MCPSchema.string("Project UUID"),
            ], required: ["project_id"])
        ),
        Tool(
            name: MCPToolName.addRow.rawValue,
            description: "Add a screenshot row (appended at the end unless an anchor row is given).",
            inputSchema: MCPSchema.object([
                "project_id": projectIdSchema,
                "before_row_id": MCPSchema.string("Insert above this row UUID"),
                "after_row_id": MCPSchema.string("Insert below this row UUID"),
                "label": MCPSchema.string("Row label"),
                "size": MCPSchema.string("Screenshot size like \"1242x2688\""),
            ])
        ),
        Tool(
            name: MCPToolName.updateRow.rawValue,
            description: "Patch row properties: label, size, background (color, gradient or image, per language if needed), blur, spanning, device visibility, default device, upload exclusion. Only provided fields change. Per-column backgrounds: update_template.",
            inputSchema: MCPSchema.object(backgroundProperties.merging([
                "project_id": projectIdSchema,
                "row_id": MCPSchema.string("Row UUID"),
                "label": MCPSchema.string("Row label"),
                "width": MCPSchema.number("Template width in pixels"),
                "height": MCPSchema.number("Template height in pixels"),
                "span_background": MCPSchema.boolean("Render the background once across all columns instead of per column"),
                "show_device": MCPSchema.boolean("Show or hide device frames in this row"),
                "device_category": MCPSchema.string("Default device category for the row: \(deviceCategoryNote)", oneOf: deviceCategories),
                "device_frame_id": MCPSchema.string("Default device frame id for the row — \(deviceFrameIdNote)"),
                "exclude_from_upload": MCPSchema.boolean("Leave this row out of App Store Connect uploads"),
            ]) { $1 }, required: ["row_id"])
        ),
        Tool(
            name: MCPToolName.moveRow.rawValue,
            description: "Move a row up or down.",
            inputSchema: MCPSchema.object([
                "project_id": projectIdSchema,
                "row_id": MCPSchema.string("Row UUID"),
                "direction": MCPSchema.string("Direction", oneOf: ["up", "down"]),
            ], required: ["row_id", "direction"])
        ),
        Tool(
            name: MCPToolName.deleteRow.rawValue,
            description: "Delete a row and its shapes.",
            inputSchema: MCPSchema.object([
                "project_id": projectIdSchema,
                "row_id": MCPSchema.string("Row UUID"),
            ], required: ["row_id"])
        ),
        Tool(
            name: MCPToolName.addTemplate.rawValue,
            description: "Add a screenshot column to a row (appended at the end unless an anchor is given).",
            inputSchema: MCPSchema.object([
                "project_id": projectIdSchema,
                "row_id": MCPSchema.string("Row UUID"),
                "before_template_id": MCPSchema.string("Insert before this template UUID"),
                "after_template_id": MCPSchema.string("Insert after this template UUID"),
            ], required: ["row_id"])
        ),
        Tool(
            name: MCPToolName.removeTemplate.rawValue,
            description: "Remove a screenshot column from a row.",
            inputSchema: MCPSchema.object([
                "project_id": projectIdSchema,
                "row_id": MCPSchema.string("Row UUID"),
                "template_id": MCPSchema.string("Template UUID"),
            ], required: ["row_id", "template_id"])
        ),
        Tool(
            name: MCPToolName.addShape.rawValue,
            description: "Add a shape to a row, styled in the same call: it accepts every update_shape field. Position defaults to the center of the given template column. Types: rectangle, circle, star, text, device (phone/tablet frame), svg (bundled preset, see list_catalog), image (from file path).",
            inputSchema: MCPSchema.object(shapeProperties.merging([
                "project_id": projectIdSchema,
                "row_id": MCPSchema.string("Row UUID"),
                "type": MCPSchema.string("Shape type", oneOf: ["rectangle", "circle", "star", "text", "device", "svg", "image"]),
                "template_index": MCPSchema.integer("Column index to center the shape in (default 0)"),
                "svg_preset": MCPSchema.string("Bundled SVG preset name (svg shapes) — list_catalog kind svg_presets"),
                "image_path": MCPSchema.string("Absolute file path of an image (image shapes). \(screenshotStagingHint)"),
            ]) { $1 }, required: ["row_id", "type"])
        ),
        Tool(
            name: MCPToolName.updateShape.rawValue,
            description: "Patch shape properties; only provided fields change. Text edits apply to the base locale (use set_translation for other locales, set_locale_layout for per-locale position and size). Text with per-range formatting (a highlighted word) reports it in get_project as text_runs; replacing `text` alone keeps only the first span's style, so edit formatted text through text_runs. Shape-level color/font/alignment/spacing fields restyle every span, translations included.",
            inputSchema: MCPSchema.object(shapeProperties.merging([
                "project_id": projectIdSchema,
                "shape_id": MCPSchema.string("Shape UUID"),
                "z_order": MCPSchema.string("Move within the stacking order", oneOf: ["front", "back"]),
            ]) { $1 }, required: ["shape_id"])
        ),
        Tool(
            name: MCPToolName.deleteShape.rawValue,
            description: "Delete a shape.",
            inputSchema: MCPSchema.object([
                "project_id": projectIdSchema,
                "shape_id": MCPSchema.string("Shape UUID"),
            ], required: ["shape_id"])
        ),
        Tool(
            name: MCPToolName.importScreenshots.rawValue,
            description: "Import screenshot images from file paths into a row's device frames. Images fill device-holding columns in order starting from the first, replacing any existing screenshots; extra images append new columns. A single column cannot be targeted — re-import the whole row's images in order. Pass `locale` to say which locale's images these are; without it they land in the project's active locale (the one the app shows), which a script cannot see. The response echoes the locale actually written. \(screenshotStagingHint)",
            inputSchema: MCPSchema.object([
                "project_id": projectIdSchema,
                "row_id": MCPSchema.string("Row UUID"),
                "paths": MCPSchema.array(of: MCPSchema.string("Absolute file path"), "Image file paths in desired order"),
                "locale": MCPSchema.string("Locale these images belong to, e.g. \"de-DE\". Use the base locale code for the images every other locale falls back to. Defaults to the project's active locale."),
                "max_templates_per_row": MCPSchema.integer("Cap on columns to create (optional)"),
            ], required: ["row_id", "paths"])
        ),
        Tool(
            name: MCPToolName.addLocale.rawValue,
            description: "Add a locale to a project (e.g. \"de-DE\", \"fr-FR\", \"ja\").",
            inputSchema: MCPSchema.object([
                "project_id": projectIdSchema,
                "code": MCPSchema.string("Locale code"),
                "label": MCPSchema.string("Display label; defaults to the preset label for known codes"),
            ], required: ["code"])
        ),
        Tool(
            name: MCPToolName.removeLocale.rawValue,
            description: "Remove a locale and all its translations from a project.",
            inputSchema: MCPSchema.object([
                "project_id": projectIdSchema,
                "code": MCPSchema.string("Locale code"),
            ], required: ["code"])
        ),
        Tool(
            name: MCPToolName.setTranslation.rawValue,
            description: "Set a text shape's translated text for a locale. Plain `text` renders in the shape's own style; pass `text_runs` instead to keep per-range formatting (get_project reports existing ones as translation_text_runs). A translation that overflows its box is fitted automatically, in this locale only: first a mild font shrink (≥80%), then a taller box into free space, and only then a deeper shrink; a later, shorter translation gives the space back. The result's `auto_fit` says what was done (`also_fitted` lists other boxes sharing the translation); when `still_overflows` is true, or `font_scale` is well below 1, shorten the translation.",
            inputSchema: MCPSchema.object(
                translationProperties.merging(["project_id": projectIdSchema]) { $1 },
                required: ["shape_id", "locale_code"]
            )
        ),
        Tool(
            name: MCPToolName.exportProject.rawValue,
            description: "Export a project's screenshots as PNG/JPEG files and return the written file paths. Without folder_path, exports to a readable temp folder. `unrenderable` lists any resource that composited to a blank area — a non-empty value means the exported images have holes in them, however many files were written.",
            inputSchema: MCPSchema.object([
                "project_id": MCPSchema.string("Project UUID to export — from list_projects"),
                "folder_path": MCPSchema.string("Destination folder (must be writable by the app; omit to use a temp folder and copy files from there)"),
                "format": MCPSchema.string("Image format (default png)", oneOf: ["png", "jpeg"]),
                "locale": MCPSchema.string("Export only this locale code (default: all locales)"),
                "naming": MCPSchema.string("File layout: standard (default) or fastlane — deliver-style <App Store locale>/<NN>_<row>.png", oneOf: ["standard", "fastlane"]),
                "row_ids": MCPSchema.array(of: MCPSchema.string("Row UUID"), "Export only these rows (default: all)"),
                "file_suffix": MCPSchema.string("Appended to every file name, e.g. \"_v2\""),
                "layout": MCPSchema.string("screenshots (default): one image per column; continuous: one stitched image per row and locale (not with fastlane naming)", oneOf: ["screenshots", "continuous"]),
            ], required: ["project_id"])
        ),
        Tool(
            name: MCPToolName.renderPreview.rawValue,
            description: "Render a row (or a single column) as a downscaled PNG image so you can see the current design.",
            inputSchema: MCPSchema.object([
                "project_id": MCPSchema.string("Project UUID that owns the row — from list_projects"),
                "row_id": MCPSchema.string("Row UUID"),
                "template_index": MCPSchema.integer("Render only this column (default: whole row)"),
                "locale": MCPSchema.string("Locale to render (default: active locale)"),
                "max_dimension": MCPSchema.integer("Longest output side in pixels, 100-1200 (default 700)"),
            ], required: ["project_id", "row_id"])
        ),
        Tool(
            name: MCPToolName.getAppStoreMetadata.rawValue,
            description: "Read App Store Connect listing metadata for the app linked to project_id: every App Store version (one per platform, e.g. iOS and macOS) with its per-locale current descriptions. Call this first to discover the exact App Store locale codes (e.g. en-US, fr-FR, de-DE, pt-BR, zh-Hans) to translate a new description into, then pass those same codes to update_app_store_description.",
            inputSchema: MCPSchema.object([
                "project_id": MCPSchema.string("Project UUID whose linked app to use; pass this or app_id"),
                "app_id": MCPSchema.string("App Store Connect app id (default: the app linked to project_id)"),
                "version_id": MCPSchema.string("Limit to a single App Store version id (default: all versions)"),
            ])
        ),
        Tool(
            name: MCPToolName.updateAppStoreDescription.rawValue,
            description: "Update only the App Store 'description' text (update_app_store_metadata covers every field) for one or more locales on App Store Connect. Supply already-translated descriptions per locale — this tool does not translate, it only applies what you give it. By default it updates every editable App Store version (all platforms); only locales that already exist on a version are updated, the rest are reported as skipped. Discover valid locale codes with get_app_store_metadata first.",
            inputSchema: MCPSchema.object([
                "project_id": MCPSchema.string("Project UUID whose linked app to use; pass this or app_id"),
                "descriptions": MCPSchema.array(
                    of: MCPSchema.object([
                        "locale": MCPSchema.string("App Store locale code, e.g. en-US, fr-FR, de-DE"),
                        "description": MCPSchema.string("Full localized description (App Store limit 4000 characters)"),
                    ], required: ["locale", "description"]),
                    "Per-locale descriptions to apply — include the base locale too"
                ),
                "app_id": MCPSchema.string("App Store Connect app id (default: the app linked to project_id)"),
                "version_id": MCPSchema.string("Update only this App Store version id (default: every editable version)"),
            ], required: ["descriptions"])
        ),
        Tool(
            name: MCPToolName.previewAppStoreScreenshotSync.rawValue,
            description: "Render a Screenshot Bro project, compare exact checksums and order with App Store Connect, and return a cached 15-minute screenshot sync plan plus a contact sheet. Ambiguous or incompatible rows/locales are reported and skipped. Above ~40 renders (rows x columns x locales) this returns immediately with a job_id and phase \"queued\" — poll get_sync_job_status. Below that it blocks and returns the same envelope with phase \"succeeded\" and the plan in `result`.",
            inputSchema: MCPSchema.object([
                "project_id": MCPSchema.string("Project UUID to render — from list_projects. Required: the app window's open project is never used as a default."),
                "app_id": MCPSchema.string("App Store Connect app id (default: the app linked to project_id)"),
                "version_ids": MCPSchema.array(of: MCPSchema.string("App Store version id"), "Editable version ids (default: every compatible editable version)"),
                "row_ids": MCPSchema.array(of: MCPSchema.string("Screenshot Bro row UUID"), "Rows to include (default: non-excluded rows with detectable display types)"),
                "locale_codes": MCPSchema.array(of: MCPSchema.string("Project locale code"), "Project locales to include (default: all project locales)"),
                "mode": MCPSchema.string("\"auto\" (default) runs small previews inline and large ones as a background job; \"sync\" blocks and is rejected above the cap; \"async\" always returns a job_id", oneOf: MCPJobMode.allCases.map(\.rawValue)),
            ], required: ["project_id"])
        ),
        Tool(
            name: MCPToolName.applyAppStoreScreenshotSync.rawValue,
            description: "Apply explicitly selected sets from a cached screenshot sync preview. Revalidates the project and every remote set, preserves matching assets, and verifies the final order. Idempotent for the same plan_id + set_ids: sets that already completed come back as \"already_applied\" and are never uploaded twice, so a call that timed out client-side is safe to retry.",
            inputSchema: MCPSchema.object([
                "plan_id": MCPSchema.string("Plan id returned by preview_app_store_screenshot_sync"),
                "project_id": MCPSchema.string("Project UUID the plan was rendered from (default: the plan's own project; a mismatch is rejected)"),
                "set_ids": MCPSchema.array(of: MCPSchema.string("Set id returned by preview"), "Explicit nonempty set selection"),
                "confirm": MCPSchema.boolean("Must be true to authorize App Store mutations"),
                "mode": MCPSchema.string("\"auto\" (default) applies small selections inline and large ones as a background job; \"sync\" blocks and is rejected above the cap; \"async\" always returns a job_id", oneOf: MCPJobMode.allCases.map(\.rawValue)),
            ], required: ["plan_id", "set_ids", "confirm"])
        ),
        Tool(
            name: MCPToolName.getSyncJobStatus.rawValue,
            description: "Poll a screenshot sync job started by preview_app_store_screenshot_sync or apply_app_store_screenshot_sync. Returns phase, completed/total, per-set state, and once the phase is \"succeeded\" the full tool payload in `result`. Terminal results are retained for 15 minutes, so a call that timed out client-side can still collect its answer.",
            inputSchema: MCPSchema.object([
                "job_id": MCPSchema.string("Job id returned by preview_ or apply_app_store_screenshot_sync"),
                "include_image": MCPSchema.boolean("Return the preview contact sheet too (default false — pass true once, after the job succeeds, rather than on every poll)"),
            ], required: ["job_id"])
        ),
        Tool(
            name: MCPToolName.cancelSyncJob.rawValue,
            description: "Request cancellation of a running screenshot sync job. Returns immediately; poll get_sync_job_status for the terminal phase. Cancelling a job that already finished is a no-op. Note that screenshots already uploaded to App Store Connect are not rolled back — check did_mutate.",
            inputSchema: MCPSchema.object([
                "job_id": MCPSchema.string("Job id to cancel"),
            ], required: ["job_id"])
        ),
        Tool(
            name: MCPToolName.listVariants.rawValue,
            description: "List a project's A/B variants and which rows belong to each. Rows with no variant are the Original — the control an App Store product page experiment compares against.",
            inputSchema: MCPSchema.object(["project_id": projectIdSchema])
        ),
        Tool(
            name: MCPToolName.createVariant.rawValue,
            description: "Start a new A/B variant by copying a row (shapes, translations and images) into it. The copy is inserted after the source row; edit it to make the alternative.",
            inputSchema: MCPSchema.object([
                "project_id": projectIdSchema,
                "from_row_id": MCPSchema.string("Row UUID to copy into the new variant"),
                "name": MCPSchema.string("Variant name (default \"Variant B\", \"Variant C\", …)"),
            ], required: ["from_row_id"])
        ),
        Tool(
            name: MCPToolName.setRowVariant.rawValue,
            description: "Move a row into a variant, or back to the Original.",
            inputSchema: MCPSchema.object([
                "project_id": projectIdSchema,
                "row_id": MCPSchema.string("Row UUID"),
                "variant_id": MCPSchema.string("Variant UUID from list_variants; omit to move the row to the Original"),
            ], required: ["row_id"])
        ),
        Tool(
            name: MCPToolName.deleteVariant.rawValue,
            description: "Delete a variant and its rows (undoable in the app). If its rows are all the project has, they move to the Original instead.",
            inputSchema: MCPSchema.object([
                "project_id": projectIdSchema,
                "variant_id": MCPSchema.string("Variant UUID from list_variants"),
            ], required: ["variant_id"])
        ),
        Tool(
            name: MCPToolName.batch.rawValue,
            description: "Apply several editing operations to one project in a single call: one undo step in the app, and all-or-nothing — if any operation fails, none is applied and the error names its index. Each operation is {tool, arguments} for one of the editing tools (add_row, update_row, move_row, delete_row, add_template, remove_template, add_shape, update_shape, delete_shape, import_screenshots, add_locale, remove_locale, set_translation, and the variant tools when enabled); leave project_id out of the operations. An id argument (row_id, shape_id, before_row_id, …) of exactly \"$N\" is replaced by the id that operation N produced (the new row's or shape's id), so later operations can edit what earlier ones created. Returns a compact record per operation, in order (ids, auto-fit, import counts); call get_project with row_ids for full snapshots.",
            inputSchema: MCPSchema.object([
                "project_id": projectIdSchema,
                "operations": MCPSchema.array(
                    of: MCPSchema.object([
                        "tool": MCPSchema.string("Editing tool name, e.g. \"add_shape\""),
                        "arguments": .object(["type": "object", "description": "That tool's arguments, without project_id"]),
                    ], required: ["tool"]),
                    "Operations, applied in order"
                ),
            ], required: ["operations"])
        ),
        Tool(
            name: MCPToolName.setTranslations.rawValue,
            description: "Set many translations in one call — one undo step, all-or-nothing. Each entry behaves like set_translation (including auto-fit) and the results come back in order.",
            inputSchema: MCPSchema.object([
                "project_id": projectIdSchema,
                "entries": MCPSchema.array(
                    of: MCPSchema.object(translationProperties, required: ["shape_id", "locale_code"]),
                    "Translations to set"
                ),
            ], required: ["entries"])
        ),
        Tool(
            name: MCPToolName.listCatalog.rawValue,
            description: "List the values other tools accept: device_frames (ids for device_frame_id, with model, category, color, orientation, screen orientation and the screenshot size each is built for — e.g. iPhone Duo inner display 2007x2853, closed 1398x2034), svg_presets (names for svg_preset), fonts (families usable as font_name in a project, including its imported fonts), locale_presets (locale codes and labels for add_locale), screenshot_sizes (App Store / Play sizes for add_row's size).",
            inputSchema: MCPSchema.object([
                "kind": MCPSchema.string("What to list", oneOf: ["device_frames", "svg_presets", "fonts", "locale_presets", "screenshot_sizes"]),
                "project_id": MCPSchema.string("For fonts: the project whose imported fonts to include (default: the open project)"),
                "category": MCPSchema.string("For device_frames: only this device category", oneOf: deviceCategories),
                "size": MCPSchema.string("For device_frames: only frames built for this screenshot size, like \"2007x2853\" (orientation matters)"),
            ], required: ["kind"])
        ),
        Tool(
            name: MCPToolName.undo.rawValue,
            description: "Undo the most recent edit in the project open in the app — the user's or an agent's, exactly like ⌘Z. Edits to a project that isn't open are saved directly and cannot be undone. Returns the name of the step undone.",
            inputSchema: MCPSchema.object([
                "project_id": MCPSchema.string("Must be the open project; guards against undoing in the wrong one"),
            ])
        ),
        Tool(
            name: MCPToolName.redo.rawValue,
            description: "Redo the most recently undone edit in the project open in the app, exactly like ⇧⌘Z.",
            inputSchema: MCPSchema.object([
                "project_id": MCPSchema.string("Must be the open project"),
            ])
        ),
        Tool(
            name: MCPToolName.updateTemplate.rawValue,
            description: "Give one screenshot column its own background instead of the row's: set override_background true plus any background fields, or false to follow the row again.",
            inputSchema: MCPSchema.object(backgroundProperties.merging([
                "project_id": projectIdSchema,
                "row_id": MCPSchema.string("Row UUID"),
                "template_id": MCPSchema.string("Template (column) UUID"),
                "override_background": MCPSchema.boolean("Use this column's own background (default: true when any background field is given)"),
            ]) { $1 }, required: ["row_id", "template_id"])
        ),
        Tool(
            name: MCPToolName.duplicateShape.rawValue,
            description: "Copy a shape with its translations and images. With to_columns, places a copy at the same spot in every other column (or only those left/right of it), like a headline repeated on each screenshot; otherwise one copy at an offset. Returns the new shape (single copy) or the row.",
            inputSchema: MCPSchema.object([
                "project_id": projectIdSchema,
                "shape_id": MCPSchema.string("Shape UUID"),
                "to_columns": MCPSchema.string("Copy into other columns", oneOf: ["all", "left", "right"]),
                "offset_x": MCPSchema.number("Single copy: horizontal offset (default 50)"),
                "offset_y": MCPSchema.number("Single copy: vertical offset (default 50)"),
            ], required: ["shape_id"])
        ),
        Tool(
            name: MCPToolName.duplicateRow.rawValue,
            description: "Copy a row (shapes, translations, images) right below it. Variant rows can't be copied in place — use create_variant.",
            inputSchema: MCPSchema.object([
                "project_id": projectIdSchema,
                "row_id": MCPSchema.string("Row UUID"),
                "label": MCPSchema.string("Label for the copy (default: \"<label> copy\")"),
            ], required: ["row_id"])
        ),
        Tool(
            name: MCPToolName.duplicateTemplate.rawValue,
            description: "Copy a screenshot column and the shapes on it, inserted right after it.",
            inputSchema: MCPSchema.object([
                "project_id": projectIdSchema,
                "row_id": MCPSchema.string("Row UUID"),
                "template_id": MCPSchema.string("Template (column) UUID"),
            ], required: ["row_id", "template_id"])
        ),
        Tool(
            name: MCPToolName.moveTemplate.rawValue,
            description: "Move a screenshot column to another position; the shapes on it move with it.",
            inputSchema: MCPSchema.object([
                "project_id": projectIdSchema,
                "row_id": MCPSchema.string("Row UUID"),
                "template_id": MCPSchema.string("Template (column) UUID"),
                "to_index": MCPSchema.integer("New 0-based column position"),
            ], required: ["row_id", "template_id", "to_index"])
        ),
        Tool(
            name: MCPToolName.replaceImage.rawValue,
            description: "Put an image into one device frame or image shape — one column, unlike import_screenshots which refills the whole row. Pass locale for a language's own screenshot. \(screenshotStagingHint)",
            inputSchema: MCPSchema.object([
                "project_id": projectIdSchema,
                "shape_id": MCPSchema.string("Device or image shape UUID"),
                "image_path": MCPSchema.string("Absolute file path of the image"),
                "locale": MCPSchema.string("Locale the image is for (default: the base image every language falls back to)"),
            ], required: ["shape_id", "image_path"])
        ),
        Tool(
            name: MCPToolName.setAllDevices.rawValue,
            description: "Switch every unlocked device frame in a row (or the whole project) to one frame or category, keeping the screenshots — e.g. to restyle a project from iPhone 17 to iPhone 17 Pro.",
            inputSchema: MCPSchema.object([
                "project_id": projectIdSchema,
                "row_id": MCPSchema.string("Row UUID (default: every row)"),
                "device_frame_id": MCPSchema.string("Device frame id — \(deviceFrameIdNote)"),
                "device_category": MCPSchema.string("Abstract device category, when no specific frame is wanted: \(deviceCategoryNote)", oneOf: deviceCategories),
            ])
        ),
        Tool(
            name: MCPToolName.arrangeShapes.rawValue,
            description: "Align or distribute shapes of one row (locked shapes are skipped), or center them in their own screenshot column.",
            inputSchema: MCPSchema.object([
                "project_id": projectIdSchema,
                "shape_ids": MCPSchema.array(of: MCPSchema.string("Shape UUID"), "Shapes in one row; align needs 2+, distribute 3+, center 1+"),
                "action": MCPSchema.string("What to do", oneOf: [
                    "align_left", "align_center", "align_right", "align_top", "align_middle", "align_bottom",
                    "distribute_horizontally", "distribute_vertically",
                    "center_in_column", "center_in_column_horizontally", "center_in_column_vertically",
                ]),
            ], required: ["shape_ids", "action"])
        ),
        Tool(
            name: MCPToolName.setBaseLocale.rawValue,
            description: "Make another locale the base: its translations become every shape's base text, and the old base becomes a translation.",
            inputSchema: MCPSchema.object([
                "project_id": projectIdSchema,
                "code": MCPSchema.string("Locale code already in the project"),
            ], required: ["code"])
        ),
        Tool(
            name: MCPToolName.setLocaleLayout.rawValue,
            description: "Give a shape its own position, size or font in one locale (e.g. a wider headline box for German), leaving the base layout alone. reset drops that locale's layout and font overrides; its text stays.",
            inputSchema: MCPSchema.object([
                "project_id": projectIdSchema,
                "shape_id": MCPSchema.string("Shape UUID"),
                "locale_code": MCPSchema.string("A non-base locale"),
                "x": MCPSchema.number("Left edge in this locale"),
                "y": MCPSchema.number("Top edge in this locale"),
                "width": MCPSchema.number("Width in this locale"),
                "height": MCPSchema.number("Height in this locale"),
                "font_size": MCPSchema.number("Font size in this locale"),
                "font_name": MCPSchema.string("Font family in this locale"),
                "font_weight": MCPSchema.integer("Font weight in this locale"),
                "text_align": MCPSchema.string("Text alignment in this locale", oneOf: ["left", "center", "right"]),
                "reset": MCPSchema.boolean("Drop this locale's position, size and font overrides first"),
            ], required: ["shape_id", "locale_code"])
        ),
        Tool(
            name: MCPToolName.updateAppStoreMetadata.rawValue,
            description: "Update App Store listing text per locale: description, keywords, promotional_text, whats_new, marketing_url and support_url on every editable version (or version_id), and name, subtitle and privacy_policy_url on the app. Only the fields you pass change. Lengths are checked against App Store Connect's limits (name and subtitle 30, keywords 100, promotional text 170, description and What's New 4000) before anything is written. Read the current text and exact locale codes with get_app_store_metadata first; this tool does not translate.",
            inputSchema: MCPSchema.object([
                "project_id": MCPSchema.string("Project UUID whose linked app to use; pass this or app_id"),
                "app_id": MCPSchema.string("App Store Connect app id (default: the app linked to project_id)"),
                "version_id": MCPSchema.string("Update only this App Store version id (default: every editable version)"),
                "locales": MCPSchema.array(
                    of: MCPSchema.object([
                        "locale": MCPSchema.string("App Store locale code, e.g. en-US, de-DE"),
                        "description": MCPSchema.string("Description (≤4000)"),
                        "keywords": MCPSchema.string("Comma-separated keywords (≤100)"),
                        "promotional_text": MCPSchema.string("Promotional text (≤170)"),
                        "whats_new": MCPSchema.string("What's New (≤4000)"),
                        "marketing_url": MCPSchema.string("Marketing URL"),
                        "support_url": MCPSchema.string("Support URL"),
                        "name": MCPSchema.string("App name (≤30)"),
                        "subtitle": MCPSchema.string("Subtitle (≤30)"),
                        "privacy_policy_url": MCPSchema.string("Privacy policy URL"),
                    ], required: ["locale"]),
                    "Per-locale changes"
                ),
            ], required: ["locales"])
        ),
        Tool(
            name: MCPToolName.listAppStoreApps.rawValue,
            description: "List the App Store Connect apps the configured API key can see, with the projects linked to each.",
            inputSchema: MCPSchema.object([:])
        ),
        Tool(
            name: MCPToolName.linkProjectStores.rawValue,
            description: "Link a project to its App Store Connect app and/or Google Play package, so store tools can find them from project_id. Pass null to unlink.",
            inputSchema: MCPSchema.object([
                "project_id": MCPSchema.string("Project UUID"),
                "app_id": MCPSchema.string("App Store Connect app id — list_app_store_apps"),
                "play_package_name": MCPSchema.string("Google Play application id, e.g. com.example.app"),
            ], required: ["project_id"])
        ),
        Tool(
            name: MCPToolName.previewPlayUpload.rawValue,
            description: "Plan a Google Play screenshot upload without touching Play: which Original rows go up as which image type (phone, 7-inch, 10-inch tablet), in which Play languages, how many screenshots, and any preflight issues. Same options as upload_play_screenshots.",
            inputSchema: MCPSchema.object(playUploadProperties, required: ["project_id"])
        ),
        Tool(
            name: MCPToolName.uploadPlayScreenshots.rawValue,
            description: "Render and upload a project's screenshots to its Google Play listing, replacing the existing screenshots of each planned image type and language. Saved as a draft edit unless send_for_review is true. Runs as a job like the App Store sync: poll get_sync_job_status. Preview with preview_play_upload first.",
            inputSchema: MCPSchema.object(playUploadProperties.merging([
                "confirm": MCPSchema.boolean("Must be true to write to Google Play"),
                "send_for_review": MCPSchema.boolean("Send the change for review instead of leaving it as a draft (default false)"),
                "mode": MCPSchema.string("\"auto\" (default), \"sync\" or \"async\" — see preview_app_store_screenshot_sync", oneOf: MCPJobMode.allCases.map(\.rawValue)),
            ]) { $1 }, required: ["project_id", "confirm"])
        ),
    ]
}
#endif
