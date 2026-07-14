#if DEBUG && os(macOS)
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
}

enum MCPToolCatalog {
    static let deviceCategories = DeviceCategory.allCases.map(\.rawValue)

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

    static let tools: [Tool] = [
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
            description: "Full structured snapshot of a project (defaults to the active one): rows, template columns, shapes, locales — including every id needed by other tools. All coordinates/sizes are in model space (pixels of the target screenshot).",
            inputSchema: MCPSchema.object([
                "project_id": MCPSchema.string("Project UUID; omit for the active project"),
            ])
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
                        "device_category": MCPSchema.string("Default device frame category", oneOf: deviceCategories),
                        "device_frame_id": MCPSchema.string("Specific device frame id (optional)"),
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
            description: "Delete a project (moves it to trash; restorable for 30 days).",
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
            description: "Add a screenshot row to the active project (appended at the end unless an anchor row is given).",
            inputSchema: MCPSchema.object([
                "before_row_id": MCPSchema.string("Insert above this row UUID"),
                "after_row_id": MCPSchema.string("Insert below this row UUID"),
                "label": MCPSchema.string("Row label"),
                "size": MCPSchema.string("Screenshot size like \"1242x2688\""),
            ])
        ),
        Tool(
            name: MCPToolName.updateRow.rawValue,
            description: "Patch row properties: label, size, background (solid color or gradient), spanning, device visibility, default device. Only provided fields change.",
            inputSchema: MCPSchema.object([
                "row_id": MCPSchema.string("Row UUID"),
                "label": MCPSchema.string("Row label"),
                "width": MCPSchema.number("Template width in pixels"),
                "height": MCPSchema.number("Template height in pixels"),
                "background_color": MCPSchema.string("Solid background color as #RRGGBB; switches background style to color"),
                "background_gradient": gradientSchema,
                "span_background": MCPSchema.boolean("Render the background once across all columns instead of per column"),
                "show_device": MCPSchema.boolean("Show or hide device frames in this row"),
                "device_category": MCPSchema.string("Default device category for the row", oneOf: deviceCategories),
                "device_frame_id": MCPSchema.string("Default device frame id for the row"),
            ], required: ["row_id"])
        ),
        Tool(
            name: MCPToolName.moveRow.rawValue,
            description: "Move a row up or down.",
            inputSchema: MCPSchema.object([
                "row_id": MCPSchema.string("Row UUID"),
                "direction": MCPSchema.string("Direction", oneOf: ["up", "down"]),
            ], required: ["row_id", "direction"])
        ),
        Tool(
            name: MCPToolName.deleteRow.rawValue,
            description: "Delete a row and its shapes.",
            inputSchema: MCPSchema.object([
                "row_id": MCPSchema.string("Row UUID"),
            ], required: ["row_id"])
        ),
        Tool(
            name: MCPToolName.addTemplate.rawValue,
            description: "Add a screenshot column to a row (appended at the end unless an anchor is given).",
            inputSchema: MCPSchema.object([
                "row_id": MCPSchema.string("Row UUID"),
                "before_template_id": MCPSchema.string("Insert before this template UUID"),
                "after_template_id": MCPSchema.string("Insert after this template UUID"),
            ], required: ["row_id"])
        ),
        Tool(
            name: MCPToolName.removeTemplate.rawValue,
            description: "Remove a screenshot column from a row.",
            inputSchema: MCPSchema.object([
                "row_id": MCPSchema.string("Row UUID"),
                "template_id": MCPSchema.string("Template UUID"),
            ], required: ["row_id", "template_id"])
        ),
        Tool(
            name: MCPToolName.addShape.rawValue,
            description: "Add a shape to a row. Position defaults to the center of the given template column. Types: rectangle, circle, star, text, device (phone/tablet frame), svg (bundled preset), image (from file path).",
            inputSchema: MCPSchema.object([
                "row_id": MCPSchema.string("Row UUID"),
                "type": MCPSchema.string("Shape type", oneOf: ["rectangle", "circle", "star", "text", "device", "svg", "image"]),
                "template_index": MCPSchema.integer("Column index to center the shape in (default 0)"),
                "x": MCPSchema.number("Left edge in model pixels (overrides template_index centering)"),
                "y": MCPSchema.number("Top edge in model pixels"),
                "width": MCPSchema.number("Width in model pixels"),
                "height": MCPSchema.number("Height in model pixels"),
                "text": MCPSchema.string("Text content (text shapes)"),
                "font_size": MCPSchema.number("Font size (text shapes)"),
                "font_name": MCPSchema.string("Font family name (text shapes)"),
                "font_weight": MCPSchema.integer("Font weight 100-900 (text shapes)"),
                "color": MCPSchema.string("Fill/text color as #RRGGBB or #RRGGBBAA"),
                "device_category": MCPSchema.string("Device category (device shapes)", oneOf: deviceCategories),
                "device_frame_id": MCPSchema.string("Device frame id (device shapes)"),
                "svg_preset": MCPSchema.string("Bundled SVG preset name (svg shapes)"),
                "image_path": MCPSchema.string("Absolute file path of an image (image shapes)"),
            ], required: ["row_id", "type"])
        ),
        Tool(
            name: MCPToolName.updateShape.rawValue,
            description: "Patch shape properties; only provided fields change. Text edits apply to the base locale (use set_translation for other locales).",
            inputSchema: MCPSchema.object([
                "shape_id": MCPSchema.string("Shape UUID"),
                "x": MCPSchema.number("Left edge in model pixels"),
                "y": MCPSchema.number("Top edge in model pixels"),
                "width": MCPSchema.number("Width in model pixels"),
                "height": MCPSchema.number("Height in model pixels"),
                "rotation": MCPSchema.number("Rotation in degrees"),
                "opacity": MCPSchema.number("Opacity 0-1"),
                "border_radius": MCPSchema.number("Corner radius (rectangles)"),
                "color": MCPSchema.string("Fill/text color as #RRGGBB or #RRGGBBAA"),
                "text": MCPSchema.string("Text content (base locale)"),
                "font_size": MCPSchema.number("Font size"),
                "font_name": MCPSchema.string("Font family name"),
                "font_weight": MCPSchema.integer("Font weight 100-900"),
                "text_align": MCPSchema.string("Horizontal text alignment", oneOf: ["left", "center", "right"]),
                "letter_spacing": MCPSchema.number("Letter spacing"),
                "line_spacing": MCPSchema.number("Line spacing"),
                "outline_color": MCPSchema.string("Outline color as #RRGGBB"),
                "outline_width": MCPSchema.number("Outline width (0 removes the outline)"),
                "device_category": MCPSchema.string("Device category (device shapes)", oneOf: deviceCategories),
                "device_frame_id": MCPSchema.string("Device frame id (device shapes)"),
                "star_points": MCPSchema.integer("Number of points (star shapes)"),
                "clip_to_template": MCPSchema.boolean("Clip the shape to its template column"),
                "locked": MCPSchema.boolean("Lock the shape against canvas interaction"),
                "z_order": MCPSchema.string("Move within the stacking order", oneOf: ["front", "back"]),
            ], required: ["shape_id"])
        ),
        Tool(
            name: MCPToolName.deleteShape.rawValue,
            description: "Delete a shape.",
            inputSchema: MCPSchema.object([
                "shape_id": MCPSchema.string("Shape UUID"),
            ], required: ["shape_id"])
        ),
        Tool(
            name: MCPToolName.importScreenshots.rawValue,
            description: "Import screenshot images from file paths into a row's device frames. Images fill device-holding columns in order starting from the first, replacing any existing screenshots; extra images append new columns. A single column cannot be targeted — re-import the whole row's images in order.",
            inputSchema: MCPSchema.object([
                "row_id": MCPSchema.string("Row UUID"),
                "paths": MCPSchema.array(of: MCPSchema.string("Absolute file path"), "Image file paths in desired order"),
                "max_templates_per_row": MCPSchema.integer("Cap on columns to create (optional)"),
            ], required: ["row_id", "paths"])
        ),
        Tool(
            name: MCPToolName.addLocale.rawValue,
            description: "Add a locale to the active project (e.g. \"de-DE\", \"fr-FR\", \"ja\").",
            inputSchema: MCPSchema.object([
                "code": MCPSchema.string("Locale code"),
                "label": MCPSchema.string("Display label; defaults to the preset label for known codes"),
            ], required: ["code"])
        ),
        Tool(
            name: MCPToolName.removeLocale.rawValue,
            description: "Remove a locale and all its translations from the active project.",
            inputSchema: MCPSchema.object([
                "code": MCPSchema.string("Locale code"),
            ], required: ["code"])
        ),
        Tool(
            name: MCPToolName.setTranslation.rawValue,
            description: "Set a text shape's translated text for a locale.",
            inputSchema: MCPSchema.object([
                "shape_id": MCPSchema.string("Text shape UUID"),
                "locale_code": MCPSchema.string("Target locale code (must exist in the project)"),
                "text": MCPSchema.string("Translated text"),
            ], required: ["shape_id", "locale_code", "text"])
        ),
        Tool(
            name: MCPToolName.exportProject.rawValue,
            description: "Export the active project's screenshots as PNG/JPEG files and return the written file paths. Without folder_path, exports to a readable temp folder.",
            inputSchema: MCPSchema.object([
                "folder_path": MCPSchema.string("Destination folder (must be writable by the app; omit to use a temp folder and copy files from there)"),
                "format": MCPSchema.string("Image format (default png)", oneOf: ["png", "jpeg"]),
                "locale": MCPSchema.string("Export only this locale code (default: all locales)"),
            ])
        ),
        Tool(
            name: MCPToolName.renderPreview.rawValue,
            description: "Render a row (or a single column) as a downscaled PNG image so you can see the current design.",
            inputSchema: MCPSchema.object([
                "row_id": MCPSchema.string("Row UUID"),
                "template_index": MCPSchema.integer("Render only this column (default: whole row)"),
                "locale": MCPSchema.string("Locale to render (default: active locale)"),
                "max_dimension": MCPSchema.integer("Longest output side in pixels, 100-1200 (default 700)"),
            ], required: ["row_id"])
        ),
    ]
}
#endif
