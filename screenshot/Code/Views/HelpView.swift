import SwiftUI

struct HelpView: View {
    static let windowID = "help"

    @State private var selection: HelpSection = .welcome

    var body: some View {
        NavigationSplitView {
            List(HelpSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.icon)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            ScrollView {
                detailContent
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .navigationTitle("Screenshot Bro Help")
        .frame(minWidth: 880, minHeight: 600)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection {
        case .shortcuts: ShortcutsHelp()
        case .support: SupportHelp()
        default: HelpEntryView(entry: selection.entry)
        }
    }
}

// MARK: - Section model

enum HelpSection: String, CaseIterable, Identifiable, Hashable {
    case welcome
    case projects
    case rows
    case templates
    case shapes
    case devices
    case backgrounds
    case editing
    case locales
    case importing
    case exporting
    case appStoreConnect
    case iCloud
    case settings
    case proFeatures
    case shortcuts
    case tips
    case support

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .welcome: "Welcome"
        case .projects: "Projects"
        case .rows: "Rows"
        case .templates: "Templates"
        case .shapes: "Shapes & Text"
        case .devices: "Devices & Frames"
        case .backgrounds: "Backgrounds"
        case .editing: "Editing on the Canvas"
        case .locales: "Languages & Translations"
        case .importing: "Importing"
        case .exporting: "Exporting"
        case .appStoreConnect: "App Store Connect"
        case .iCloud: "iCloud Sync"
        case .settings: "Settings & Defaults"
        case .proFeatures: "Free vs Pro"
        case .shortcuts: "Keyboard Shortcuts"
        case .tips: "Tips & Tricks"
        case .support: "Support & Feedback"
        }
    }

    var icon: String {
        switch self {
        case .welcome: "sparkles"
        case .projects: "folder"
        case .rows: "rectangle.stack"
        case .templates: "rectangle.split.3x1"
        case .shapes: "square.on.circle"
        case .devices: "iphone"
        case .backgrounds: "paintpalette"
        case .editing: "hand.draw"
        case .locales: "globe"
        case .importing: "square.and.arrow.down"
        case .exporting: "square.and.arrow.up"
        case .appStoreConnect: "arrow.up.circle"
        case .iCloud: "icloud"
        case .settings: "gear"
        case .proFeatures: "star"
        case .shortcuts: "keyboard"
        case .tips: "lightbulb"
        case .support: "questionmark.circle"
        }
    }
}

struct HelpEntry {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    let blocks: [HelpBlock]
}

enum HelpBlock {
    case heading(LocalizedStringKey)
    case paragraph(LocalizedStringKey)
    case bullet(LocalizedStringKey)
    case tip(LocalizedStringKey)
}

// MARK: - Section content

private struct HelpEntryView: View {
    let entry: HelpEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HelpHeader(entry.title, subtitle: entry.subtitle)
            ForEach(Array(entry.blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let text): HelpHeading(text)
                case .paragraph(let text): HelpParagraph(text)
                case .bullet(let text): HelpBullet(text)
                case .tip(let text): HelpTip(text)
                }
            }
        }
    }
}

// MARK: - Building blocks

private struct HelpHeader: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?

    init(_ title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: UIMetrics.FontSize.displayTitle, weight: .bold))
            if let subtitle {
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 8)
    }
}

private struct HelpHeading: View {
    let text: LocalizedStringKey
    let topPadding: CGFloat

    init(_ text: LocalizedStringKey, topPadding: CGFloat = 12) {
        self.text = text
        self.topPadding = topPadding
    }

    var body: some View {
        Text(text)
            .font(.system(size: UIMetrics.FontSize.sectionHeading, weight: .semibold))
            .padding(.top, topPadding)
    }
}

private struct HelpParagraph: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }
    var body: some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct HelpBullet: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•").foregroundStyle(.secondary)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct HelpTip: View {
    private static let fillOpacity: Double = 0.08
    private static let borderOpacity: Double = 0.25

    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(.yellow)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.yellow.opacity(Self.fillOpacity),
            in: RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.section, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.section, style: .continuous)
                .stroke(Color.yellow.opacity(Self.borderOpacity), lineWidth: UIMetrics.BorderWidth.hairline)
        )
    }
}

private struct ShortcutRow: View {
    let keys: String
    let description: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(keys)
                .font(.system(.body, design: .monospaced).weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Color.primary.opacity(UIMetrics.Opacity.sectionFill),
                    in: RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.chip)
                )
                .frame(minWidth: 160, alignment: .leading)
            Text(description)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Section data

extension HelpSection {
    var entry: HelpEntry {
        switch self {
        case .welcome: welcomeEntry
        case .projects: projectsEntry
        case .rows: rowsEntry
        case .templates: templatesEntry
        case .shapes: shapesEntry
        case .devices: devicesEntry
        case .backgrounds: backgroundsEntry
        case .editing: editingEntry
        case .locales: localesEntry
        case .importing: importingEntry
        case .exporting: exportingEntry
        case .appStoreConnect: appStoreConnectEntry
        case .iCloud: iCloudEntry
        case .settings: settingsEntry
        case .proFeatures: proFeaturesEntry
        case .tips: tipsEntry
        case .shortcuts, .support:
            HelpEntry(title: title, subtitle: nil, blocks: [])
        }
    }

    private var welcomeEntry: HelpEntry {
        HelpEntry(
            title: "Welcome to Screenshot Bro",
            subtitle: "Beautiful App Store and Google Play screenshots, made on your Mac.",
            blocks: [
                .paragraph("Screenshot Bro turns raw device screenshots into polished, store-ready marketing images. Drop in a screenshot, pick a device frame, add a headline, and export at exactly the resolution the App Store and Google Play expect."),
                .heading("Three things to know first"),
                .bullet("**Projects** hold one screenshot set per app — usually one project per app, or one per major release."),
                .bullet("**Rows** inside a project group screenshots by device type (iPhone, iPad, Android phone, etc.). Each device size gets its own row because the App Store requires different resolutions."),
                .bullet("**Templates** are the columns inside a row — the individual screenshots you'll submit. Most apps need 3–10 templates per row."),
                .heading("A typical workflow"),
                .bullet("1. Create a new project from a template, or start blank."),
                .bullet("2. Drop your raw device screenshots onto the templates — Screenshot Bro detects iPhone vs iPad vs Android from the image dimensions and routes them to the right row."),
                .bullet("3. Pick a device frame, add a headline, choose a background, and arrange shapes."),
                .bullet("4. Add languages you support — translate text once and let the layout follow."),
                .bullet("5. Export. You'll get a folder organized by language and device, ready to upload."),
                .tip("If this is your first time, the **Onboarding** sheet will walk you through picking a default screenshot size and device. Pick a new project from a template any time via **File ▸ New Project**."),
            ]
        )
    }

    private var projectsEntry: HelpEntry {
        HelpEntry(
            title: "Projects",
            subtitle: "One project per app — or per major release.",
            blocks: [
                .paragraph("A project is a self-contained collection of rows, templates, shapes, languages, and image resources. Projects are stored on disk under your user Application Support folder and can be optionally synced via iCloud Drive."),
                .heading("Creating a project"),
                .bullet("**File ▸ New Project…** (⌘N) opens the New Project window."),
                .bullet("Choose **Blank** to set up rows and screenshot sizes manually, or **From Template** to start with a pre-designed layout."),
                .bullet("In Blank mode, pick the device categories you want — each one becomes a row with the right default screenshot size for the App Store / Play Store."),
                .heading("Switching between projects"),
                .bullet("Use the project picker in the toolbar to jump between projects."),
                .bullet("Pinned and recent projects appear at the top."),
                .bullet("Project order can be set to **Creation date** or **Manual** in Settings ▸ General."),
                .heading("Renaming, duplicating, deleting"),
                .bullet("Right-click a project in the picker for rename, duplicate, and delete actions."),
                .bullet("Deleted projects are kept as **tombstones** for 30 days so iCloud sync can resolve conflicts cleanly. After 30 days the tombstone (and all images) are purged."),
                .heading("Where projects live on disk"),
                .bullet("`~/Library/Application Support/screenshot/projects.json` — index of all projects."),
                .bullet("`~/Library/Application Support/screenshot/projects/<uuid>/project.json` — project data."),
                .bullet("`~/Library/Application Support/screenshot/projects/<uuid>/resources/` — imported images, screenshots, and SVGs."),
                .tip("Projects autosave 0.3 seconds after the last change. You don't need to manually save. To make a one-off backup, use **Settings ▸ Export ▸ Back Up Projects**."),
            ]
        )
    }

    private var rowsEntry: HelpEntry {
        HelpEntry(
            title: "Rows",
            subtitle: "One row per device type.",
            blocks: [
                .paragraph("Rows are horizontal groups of screenshots inside a project. Each row has its own screenshot size (in pixels), device category, and a row-level background. The App Store requires separate uploads per device size — that's why rows exist."),
                .heading("Adding rows"),
                .bullet("Click **Add Row** at the bottom of the canvas, or use the inspector when no row is selected."),
                .bullet("Choose a device category: **iPhone**, **iPad Pro 11\"**, **iPad Pro 13\"**, **MacBook**, **Android Phone**, **Android Tablet**, or **Invisible** (an abstract layout with no visible frame)."),
                .bullet("Each category sets the row's default screenshot pixel size to a value the relevant store accepts."),
                .heading("Row inspector"),
                .bullet("Select a row (click empty canvas space inside it) to reveal row-level controls in the inspector."),
                .bullet("**Row label** — names the folder this row exports into."),
                .bullet("**Screenshot size presets** — quickly switch between supported store resolutions."),
                .bullet("**Background editor** — color, gradient, or image. See the **Backgrounds** topic."),
                .bullet("**Spanning background** — when on, the background spans the entire row width across all templates. When off, every template paints the same background independently."),
                .heading("Reordering and deleting"),
                .bullet("Drag a row's header to reorder. Use **⌘D** to duplicate a selected row."),
                .bullet("**Delete** removes the row. Settings ▸ General has a confirmation toggle."),
                .tip("If you only see one row, you may be on the **Free** tier (limit: 3 rows per project). Upgrading to Pro removes this limit. See **Free vs Pro**."),
            ]
        )
    }

    private var templatesEntry: HelpEntry {
        HelpEntry(
            title: "Templates",
            subtitle: "The individual screenshots inside a row.",
            blocks: [
                .paragraph("Each column inside a row is a template. A template is one final exported image — its dimensions match the row's screenshot size. The App Store accepts up to 10 templates per row; Google Play up to 8."),
                .heading("Adding templates"),
                .bullet("Click **Add Template** (the **+** button at the right end of the row)."),
                .bullet("New templates inherit the row's background and dimensions."),
                .bullet("Drag templates left/right to reorder. Reordering also reorders the exported file numbering."),
                .heading("Per-template controls"),
                .bullet("The **Template Control Bar** below each template lets you override the row background just for that template."),
                .bullet("Drop a screenshot directly onto a template to attach it as the device screenshot."),
                .bullet("The **⋯ menu** offers per-template actions like duplicate, delete, and export preview."),
                .heading("How shapes relate to templates"),
                .bullet("Shapes (text, images, devices, etc.) live on the **row canvas** — the unified area behind all templates in a row. A shape can be positioned to land entirely inside one template, or to span across templates."),
                .bullet("On export, each template is clipped to its own bounds, so a shape that spans templates will appear on each of them at the right horizontal offset."),
                .bullet("This is what makes layouts like a single headline that flows across two screenshots possible."),
                .tip("Free tier limit: 5 templates per row. Pro removes this limit. See **Free vs Pro**."),
            ]
        )
    }

    private var shapesEntry: HelpEntry {
        HelpEntry(
            title: "Shapes & Text",
            subtitle: "Build the layout with rectangles, circles, stars, text, images, devices, and SVGs.",
            blocks: [
                .heading("Adding shapes"),
                .bullet("Use the **Shapes** dropdown in the inspector to add a Rectangle, Circle, or Star."),
                .bullet("Buttons next to it add Text, Image, Device, or SVG elements."),
                .bullet("New shapes are placed at the center of the active template and immediately selected."),
                .heading("Text"),
                .bullet("Double-click a text shape to edit inline. Press **Esc** or click outside to commit."),
                .bullet("The properties bar shows font, weight, size, color, alignment, line height, and letter spacing."),
                .bullet("Text auto-grows vertically by default. Drag a side handle to fix the width and let it wrap."),
                .bullet("Custom fonts: import via **Settings ▸ General ▸ Custom Fonts**."),
                .heading("Image"),
                .bullet("Click the image well in the properties bar to pick a file, or drag and drop directly onto the shape."),
                .bullet("Fill modes: **Fill** (crop to fit), **Fit** (letterbox), **Stretch** (distort), **Tile** (repeat). Tile mode unlocks spacing, offset, and scale controls."),
                .bullet("Add an outline, corner radius, or rotation from the properties bar."),
                .heading("Device"),
                .bullet("Device shapes render the screenshot inside a real device frame. Pick a category and model in the properties bar."),
                .bullet("**Drop a screenshot onto the device** to attach it. The image is automatically clipped to the screen area."),
                .bullet("Each model has color variants and (where applicable) a landscape variant."),
                .bullet("**Invisible** category shows the screenshot with no bezel — useful for clipped or abstract designs."),
                .heading("SVG"),
                .bullet("Click **SVG** to import a vector file. Or paste raw SVG via the SVG paste dialog."),
                .bullet("SVGs render with a configurable color override and scale crisply at any export resolution."),
                .bullet("During resize, rendering is debounced for performance — release the mouse to see the final crisp output."),
                .heading("Common properties"),
                .bullet("Color, opacity, rotation (in degrees, editable as text), border radius, outline (color + width), and a clip toggle (clips overflow to the shape)."),
                .bullet("Z-order: **⌘⇧]** brings forward, **⌘⇧[** sends back."),
            ]
        )
    }

    private var devicesEntry: HelpEntry {
        HelpEntry(
            title: "Devices & Frames",
            subtitle: "Real device frames with accurate screen insets.",
            blocks: [
                .paragraph("Device frames wrap your screenshot in an authentic phone or tablet bezel. Screenshot Bro ships pixel-accurate frames for the latest iPhones, iPads, MacBooks, and a generic Android catalog."),
                .heading("Categories"),
                .bullet("**iPhone** — iPhone 17, Air, Pro, Pro Max with the latest color variants."),
                .bullet("**iPad Pro 11\"** and **iPad Pro 13\"** — current generation with portrait and landscape."),
                .bullet("**MacBook** — MacBook Air 13\", MacBook Pro 14\", MacBook Pro 16\", iMac 24\"."),
                .bullet("**Android Phone** and **Android Tablet** — generic frames that flex to match the aspect ratio of any dropped screenshot."),
                .bullet("**Invisible** — no visible bezel, just the screenshot. Useful for clipped layouts or abstract designs."),
                .heading("Picking a model and color"),
                .bullet("With a device shape selected, click the device thumbnail in the properties bar to open the picker."),
                .bullet("Models are grouped by category. Each shows available colors as small swatches."),
                .bullet("Switching color preserves the screenshot and any rotation."),
                .heading("Landscape mode"),
                .bullet("Devices that support landscape (iPad, MacBook) auto-rotate the frame to match the dropped screenshot's aspect ratio."),
                .bullet("Manual rotation via the rotation control on the properties bar rotates the entire shape including frame and screen content."),
                .heading("Image-based vs programmatic frames"),
                .bullet("Most modern devices use **image-based frames** — high-res PNG bezels with precise screen insets defined per model."),
                .bullet("Some abstract categories use **programmatic frames** rendered as SwiftUI shapes. They scale flawlessly to any resolution."),
                .bullet("Both render identically in the editor preview and in the exported PNG."),
                .tip("If you drop a screenshot onto an empty template (not a device shape), Screenshot Bro creates a device shape automatically using the row's category and the right model based on the screenshot's pixel size."),
            ]
        )
    }

    private var backgroundsEntry: HelpEntry {
        HelpEntry(
            title: "Backgrounds",
            subtitle: "Color, gradient, or image — at row or template level.",
            blocks: [
                .heading("Three styles"),
                .bullet("**Color** — a solid fill picked from the inline color picker."),
                .bullet("**Gradient** — Linear, Radial, or Angular. Edit color stops, angle, and (for Radial / Angular) the center point."),
                .bullet("**Image** — bring in any PNG / JPEG / SVG. Pick a fill mode and tweak opacity."),
                .heading("Gradients"),
                .bullet("**Linear**: choose start/end via the angle wheel. Add as many stops as you want."),
                .bullet("**Radial**: a circular gradient with an editable center point and end radius derived from the canvas size."),
                .bullet("**Angular**: a sweep gradient rotating around the center."),
                .bullet("**Gradient presets**: pick from the preset gallery to apply tested stop combinations."),
                .heading("Image fill modes"),
                .bullet("**Fill** — scales to cover; crops anything that doesn't fit."),
                .bullet("**Fit** — scales so the whole image is visible; leaves transparent letterbox bars."),
                .bullet("**Stretch** — fills exactly, distorting aspect if needed."),
                .bullet("**Tile** — repeats the image with adjustable spacing, offset, and scale per axis."),
                .heading("Row vs template backgrounds"),
                .bullet("By default a row's background applies to every template in the row."),
                .bullet("**Spanning background** (row toggle): when on, gradients and images render once across the entire row, so a single horizon or gradient flows across all templates."),
                .bullet("**Override per template**: from the template control bar, set a unique background that replaces the row's default just for that template."),
                .tip("Spanning is great for storytelling: a sunset gradient or a single panoramic image can stretch across three templates and tell a continuous visual story in the App Store carousel."),
            ]
        )
    }

    private var editingEntry: HelpEntry {
        HelpEntry(
            title: "Editing on the Canvas",
            subtitle: "Drag, resize, rotate, snap.",
            blocks: [
                .heading("Selection"),
                .bullet("Click a shape to select it. **Shift-click** to add to or remove from the selection."),
                .bullet("**⌘A** selects every shape in the active row."),
                .bullet("**Esc** deselects shapes; press again to deselect the row."),
                .bullet("Click empty canvas inside a row to select the row itself and reveal row-level inspector controls."),
                .heading("Move, resize, rotate"),
                .bullet("Drag the shape body to move. Drag a corner or edge handle to resize."),
                .bullet("Drag the rotation handle (above the shape) to rotate freely. Type a degree value into the rotation field for exact control."),
                .bullet("Hold **⇧** while resizing to lock aspect ratio."),
                .bullet("Hold **⌥** while dragging to duplicate the shape as you move."),
                .heading("Snapping & alignment guides"),
                .bullet("Shapes snap to other shapes' edges and centers, and to template boundaries, within a 4px threshold."),
                .bullet("Blue **alignment guides** appear while dragging to show which edges are aligned."),
                .heading("Nudge"),
                .bullet("Arrow keys nudge the selection by 1px."),
                .bullet("**⇧ + Arrow** nudges by 10px."),
                .heading("Pan & zoom"),
                .bullet("Scroll vertically to navigate rows."),
                .bullet("Hold the **middle mouse button** and drag to pan."),
                .bullet("**⌘+** / **⌘−** zoom in/out, **⌘0** resets to 100%, **F** focuses on the current selection."),
                .bullet("The zoom slider in the toolbar ranges from 50% to 200% in 25% steps."),
                .tip("If a shape spans across templates and you only see part of it, that's expected — each template clips shapes to its own bounds. Switch to a different template view or use **F** to focus on the whole shape."),
            ]
        )
    }

    private var localesEntry: HelpEntry {
        HelpEntry(
            title: "Languages & Translations",
            subtitle: "Translate text once, lay it out once, ship every language.",
            blocks: [
                .paragraph("Languages let you generate localized screenshot sets without duplicating your project. Each language shares the same layout and shapes; only text properties (content, font, size, alignment) are overridden per language."),
                .heading("Adding languages"),
                .bullet("Open the **Language** menu in the toolbar, or use **Language ▸ Manage Languages…** in the menu bar."),
                .bullet("Pick from 30 built-in language presets, or define a custom code."),
                .bullet("The first language you add is the **base language** — the one whose text is the source of truth."),
                .heading("Switching the active language"),
                .bullet("**⌘]** / **⌘[** cycle forward / backward through languages."),
                .bullet("**⌘⌥0** jumps back to the base language."),
                .bullet("When editing a non-base language, a banner appears at the top of the canvas reminding you which language you're in."),
                .heading("How translations work"),
                .bullet("In a non-base language, edits to text shapes are saved as **per-language overrides** — they don't change the base."),
                .bullet("Other shape properties (position, size, color, image) are shared across all languages. Edit them once and every language picks up the change."),
                .bullet("If a language has no override for a text shape, it falls back to the base language's text."),
                .heading("Translation helpers"),
                .bullet("**Auto-Translate Missing Text** — fills in text shapes that don't yet have an override for the current language."),
                .bullet("**Re-Translate All Text…** — replaces every existing override with a fresh translation. Use after editing the base language's text."),
                .bullet("**Translate Selected to All Languages** — appears in the language bar when editing the base language with text shapes selected. Translates the selection into every other language at once."),
                .bullet("**Revert to Base Language…** — drops all overrides for the current language, falling back to base text everywhere."),
                .bullet("**Edit Translations…** — open a side-by-side editor showing every text shape with its base content and per-language overrides."),
                .heading("Exporting with languages"),
                .bullet("On export, Screenshot Bro creates one folder per language, then sub-folders per row. The structure matches what App Store Connect's localized screenshot uploads expect."),
            ]
        )
    }

    private var importingEntry: HelpEntry {
        HelpEntry(
            title: "Importing",
            subtitle: "Drop screenshots, images, fonts, and SVGs.",
            blocks: [
                .heading("Screenshots"),
                .bullet("Drag and drop a PNG / JPEG onto a template to attach it as a device screenshot. A device shape is auto-created if needed."),
                .bullet("**Batch import**: drop multiple screenshots at once. Screenshot Bro inspects each image's pixel dimensions and routes it to the matching device row (iPhone vs iPad vs Android)."),
                .bullet("If a screenshot doesn't match any existing row, a new row is offered."),
                .heading("Background images"),
                .bullet("Drop directly into the background image well in the inspector, or pick via the file dialog."),
                .bullet("Both raster and SVG images are supported as backgrounds."),
                .heading("SVG paste"),
                .bullet("Use the **SVG** button in the shape toolbar to open the paste dialog."),
                .bullet("Paste SVG markup directly. Width and height are auto-detected; you can override them."),
                .bullet("SVGs are sanitized — script and event handlers are stripped before rendering."),
                .heading("Custom fonts"),
                .bullet("**Settings ▸ General ▸ Custom Fonts** — pick `.otf` / `.ttf` files to register them with the app."),
                .bullet("Imported fonts are bundled with the project so they survive iCloud sync and project transfer."),
                .bullet("Fonts appear in the text shape font picker once registered."),
                .tip("To capture screenshots from a connected simulator quickly, use the screenshot capture button in the template control bar — it pulls the most recent simulator screenshot directly into the template."),
            ]
        )
    }

    private var exportingEntry: HelpEntry {
        HelpEntry(
            title: "Exporting",
            subtitle: "Produce store-ready PNGs and JPEGs.",
            blocks: [
                .heading("Quick export"),
                .bullet("Click **Export** in the toolbar to render the current project to PNG."),
                .bullet("By default, Screenshot Bro exports every language, every row, and every template at 1× scale."),
                .bullet("File names are zero-padded (`01_…`, `02_…`) so they sort correctly when uploaded."),
                .heading("Format and scale"),
                .bullet("**Settings ▸ Export ▸ Format**: PNG or JPEG. PNG is recommended for marketing screenshots."),
                .bullet("**Scale**: 1×, 2×, or 3×. The App Store and Google Play require exact pixel dimensions, so keep this at 1× unless you specifically need oversized assets."),
                .heading("Folder structure"),
                .bullet("With one language and one row: a flat folder of templates."),
                .bullet("With multiple languages: a top-level folder per language."),
                .bullet("With multiple rows: a sub-folder per row label (e.g. `iPhone 6.9\"`, `iPad 13\"`)."),
                .bullet("This mirrors the upload flow expected by App Store Connect's localized screenshot uploader."),
                .heading("Export folder memory"),
                .bullet("Screenshot Bro remembers the last folder you exported to (security-scoped bookmark)."),
                .bullet("Toggle **Open export folder on success** in Settings to auto-reveal the result in Finder."),
                .heading("Preview vs export"),
                .bullet("Use the **Export Preview** button in the template control bar to render a single template to a preview window — handy for spot-checking without going through the full export flow."),
                .bullet("Editor and export must always match exactly. If they don't, please report it as a bug."),
            ]
        )
    }

    private var appStoreConnectEntry: HelpEntry {
        HelpEntry(
            title: "App Store Connect",
            subtitle: "Upload screenshots straight from Screenshot Bro.",
            blocks: [
                .paragraph("Connect your App Store Connect API key once and Screenshot Bro can upload exported screenshots to a specific app version without leaving the app."),
                .heading("Set up an API key"),
                .bullet("Go to **App Store Connect ▸ Users and Access ▸ Integrations ▸ App Store Connect API**."),
                .bullet("Create a key with **App Manager** access. Download the `.p8` private key file (you can only download it once)."),
                .bullet("Note the **Issuer ID** and **Key ID**."),
                .bullet("In Screenshot Bro: **Settings ▸ App Store Connect**, paste the Issuer ID and Key ID, and import the `.p8` file."),
                .heading("Uploading"),
                .bullet("Run an export first, then click **Upload to App Store Connect** in the toolbar."),
                .bullet("Pick the app and version. Screenshot Bro maps each row to the right device family automatically."),
                .bullet("You can preview which screenshots will be uploaded for which locale before confirming."),
                .tip("App Store Connect allows up to 10 screenshots per device family per locale. Screenshot Bro respects template ordering so the first 10 templates in each row will be uploaded in order."),
            ]
        )
    }

    private var iCloudEntry: HelpEntry {
        HelpEntry(
            title: "iCloud Sync",
            subtitle: "Edit on one Mac, continue on another.",
            blocks: [
                .paragraph("iCloud sync keeps your project library in iCloud Drive (`iCloud.xyz.tleskiv.screenshot`). Changes made on one Mac propagate to others signed into the same iCloud account."),
                .heading("Enabling"),
                .bullet("**Settings ▸ General ▸ iCloud Sync** — toggle on."),
                .bullet("First-time enable migrates your local project library into iCloud. A progress indicator shows the migration."),
                .bullet("Disabling does **not** delete your iCloud data — your projects remain in the iCloud container until you delete them manually."),
                .heading("How conflicts are resolved"),
                .bullet("Each project is merged using a **last-writer-wins** strategy at the field level. The most recently edited shape, row, or background wins."),
                .bullet("Deletions are tracked as **tombstones** for 30 days, so a delete on Mac A correctly propagates to Mac B even if the device is offline at the moment of deletion."),
                .bullet("File coordination (`NSFileCoordinator`) prevents corruption from concurrent reads/writes."),
                .heading("Knowing what's syncing"),
                .bullet("The toolbar shows an iCloud status icon when an upload or download is in progress."),
                .bullet("Behind the scenes, an `NSMetadataQuery` watches each project for upload/download progress."),
                .tip("If sync seems stuck, open Finder ▸ iCloud Drive ▸ Screenshot Bro and check whether files are still uploading. Toggling iCloud off and on again forces a re-scan."),
            ]
        )
    }

    private var settingsEntry: HelpEntry {
        HelpEntry(
            title: "Settings & Defaults",
            subtitle: "Tune the app to match your workflow.",
            blocks: [
                .heading("General"),
                .bullet("**Appearance** — Auto / Light / Dark."),
                .bullet("**Language** — override the app interface language. Requires a relaunch."),
                .bullet("**Default screenshot size** — used when creating new rows."),
                .bullet("**Default device** — pre-selects a device category and model for new rows."),
                .bullet("**Default templates per row** — number of empty templates a new row starts with."),
                .bullet("**Default zoom** — initial zoom level when opening the app."),
                .bullet("**Confirm before deleting** — show a confirmation prompt for destructive actions on rows and screenshots."),
                .bullet("**Project order** — Creation date or Manual."),
                .bullet("**Custom fonts** — manage imported `.otf`/`.ttf` files."),
                .bullet("**iCloud sync** — toggle and check status."),
                .bullet("**Back up projects** — write a one-off zip of your project library to a folder you choose."),
                .heading("Export"),
                .bullet("**Format** — PNG or JPEG."),
                .bullet("**Scale** — 1×, 2×, 3×."),
                .bullet("**Open export folder on success** — auto-reveal results in Finder."),
                .bullet("**Last export folder** — Screenshot Bro remembers and reuses your folder choice."),
                .heading("App Store Connect"),
                .bullet("API key, Issuer ID, Key ID. See the App Store Connect topic."),
                .heading("Purchase"),
                .bullet("Current plan, restore purchases, manage subscription."),
                .heading("Attributions"),
                .bullet("Credits and licenses for fonts, icons, and bundled assets."),
            ]
        )
    }

    private var proFeaturesEntry: HelpEntry {
        HelpEntry(
            title: "Free vs Pro",
            subtitle: "What's included and where Pro unlocks more.",
            blocks: [
                .heading("Free tier"),
                .bullet("**1 project** — you can keep editing it forever."),
                .bullet("**3 rows** per project."),
                .bullet("**5 templates** per row."),
                .bullet("Full access to all device frames, shapes, languages, and export resolutions."),
                .bullet("Watermark-free exports."),
                .heading("Pro"),
                .bullet("Unlimited projects, rows, and templates."),
                .bullet("App Store Connect upload."),
                .bullet("iCloud sync."),
                .bullet("Future Pro-only features as they ship."),
                .heading("Buying or restoring"),
                .bullet("**Settings ▸ Purchase** lists the available plans. RevenueCat handles the transaction."),
                .bullet("**Restore Purchases** brings back an existing subscription on a new Mac."),
                .bullet("Subscriptions are managed through your Apple ID; cancellations happen via System Settings ▸ Apple ID ▸ Subscriptions."),
                .tip("Pro paywall messages adapt to context — the prompt you see when adding a 4th row is different from the one you see when adding a 6th template, so you always know exactly which limit you're hitting."),
            ]
        )
    }

    private var tipsEntry: HelpEntry {
        HelpEntry(
            title: "Tips & Tricks",
            subtitle: "Small things that save time.",
            blocks: [
                .bullet("**Drop folders, not files.** Drag a folder of screenshots onto the canvas — Screenshot Bro will batch-import and route by device size."),
                .bullet("**Span backgrounds for storytelling.** Turn on row spanning and use a wide gradient or panoramic image to make a 3-template carousel feel like one continuous scene."),
                .bullet("**Lock aspect when resizing icons** by holding **⇧** while dragging a corner handle."),
                .bullet("**Duplicate while dragging** with **⌥**. Combined with snap, this is the fastest way to lay out a row of equal-sized cards."),
                .bullet("**Type rotation degrees directly.** The rotation field accepts text input — type `45` for an exact 45° rotation instead of dragging."),
                .bullet("**Use the SVG button for icons.** SVG scales infinitely, so your hero icon stays crisp at 1×, 2×, or 3× export."),
                .bullet("**Re-translate after editing base text.** If you change the base headline, run **Language ▸ Re-Translate All Text…** (or use **Translate Selected to All Languages** in the language bar with the edited text selected) so every language picks up the new wording."),
                .bullet("**Use Invisible category for clipped designs.** When you want the screenshot to bleed off the canvas with no bezel, pick the Invisible device category."),
                .bullet("**Pin frequently used projects.** Right-click in the project picker to pin and keep them at the top."),
                .bullet("**Preview before exporting.** The export preview button on each template renders just that one template — handy for spot-checks."),
                .bullet("**Custom fonts persist.** Imported fonts are bundled per project, so a project shared via iCloud or zip backup keeps its typography."),
            ]
        )
    }
}

// MARK: - Bespoke sections

private struct ShortcutsHelp: View {
    private struct Group {
        let title: LocalizedStringKey
        let rows: [(keys: String, description: LocalizedStringKey)]
    }

    private let groups: [Group] = [
        Group(title: "File", rows: [
            ("⌘N", "New project")
        ]),
        Group(title: "Edit", rows: [
            ("⌘C", "Copy selected shapes (or text in fields)"),
            ("⌘X", "Cut selected shapes"),
            ("⌘V", "Paste shapes"),
            ("⌘A", "Select all shapes in the active row"),
            ("⌘D", "Duplicate selected shapes / row"),
            ("Delete", "Delete selected shapes"),
            ("Esc", "Deselect"),
            ("⌘⇧]", "Bring shape to front"),
            ("⌘⇧[", "Send shape to back"),
            ("← → ↑ ↓", "Nudge selection by 1px"),
            ("⇧ + Arrow", "Nudge selection by 10px"),
            ("⌥ + Drag", "Duplicate while dragging"),
        ]),
        Group(title: "View", rows: [
            ("⌘+", "Zoom in"),
            ("⌘−", "Zoom out"),
            ("⌘0", "Actual size (100%)"),
            ("F", "Focus on selection"),
            ("Middle-click + drag", "Pan canvas"),
        ]),
        Group(title: "Language", rows: [
            ("⌘]", "Next language"),
            ("⌘[", "Previous language"),
            ("⌘⌥0", "Switch to base language"),
        ]),
        Group(title: "Text editing", rows: [
            ("Double-click text", "Enter inline edit mode"),
            ("Esc / click outside", "Commit text edit"),
        ]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HelpHeader("Keyboard Shortcuts", subtitle: "Everything you can do without the mouse.")
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                VStack(alignment: .leading, spacing: 8) {
                    HelpHeading(group.title, topPadding: 0)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(group.rows.enumerated()), id: \.offset) { _, row in
                            ShortcutRow(keys: row.keys, description: row.description)
                        }
                    }
                }
            }
        }
    }
}

private struct SupportHelp: View {
    private let supportEmail = "leskiv.taras@gmail.com"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HelpHeader("Support & Feedback", subtitle: "We read every message.")

            HelpHeading("Get in touch")
            HelpBullet("Email: \(supportEmail)")
            HelpBullet("Website: [screenshotbro.app](https://screenshotbro.app)")

            HelpHeading("When reporting a bug")
            HelpParagraph("To help us reproduce, please include:")
            HelpBullet("macOS version (Apple menu ▸ About This Mac).")
            HelpBullet("Screenshot Bro version (Apple menu ▸ About Screenshot Bro).")
            HelpBullet("Steps to reproduce, ideally with a screen recording.")
            HelpBullet("If the issue affects a project, **Settings ▸ Export ▸ Back Up Projects** and attach the resulting backup so we can reproduce on the exact data.")

            HelpHeading("Legal")
            HelpBullet("[Privacy Policy](https://screenshotbro.app/privacy)")
            HelpBullet("[Terms of Service](https://screenshotbro.app/terms)")

            HelpTip("Loved the app? An App Store review helps tremendously and keeps Screenshot Bro independent.")
        }
    }
}
