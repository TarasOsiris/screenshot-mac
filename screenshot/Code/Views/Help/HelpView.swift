import SwiftUI

#if os(macOS)
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
            .background(Color.platformTextBackground)
        }
        .navigationTitle("Screenshot Bro Help")
        .frame(minWidth: 880, minHeight: 600)
        .background(WindowSceneBridge(role: .help))
        .screenView(.help)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection {
        // The only bespoke page: its rows are key caps, not prose blocks.
        case .shortcuts: ShortcutsHelp()
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
    case showcase
    case appStoreConnect
    case googlePlay
    case iCloud
    case automation
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
        case .showcase: "Showcase Export"
        case .appStoreConnect: "App Store Connect"
        case .googlePlay: "Google Play"
        case .iCloud: "iCloud Sync"
        case .automation: "Automation & MCP"
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
        case .showcase: "photo.stack"
        case .appStoreConnect: "arrow.up.circle"
        case .googlePlay: "play.rectangle.on.rectangle"
        case .iCloud: "icloud"
        case .automation: "terminal"
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
        .overlay {
            RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.section, style: .continuous)
                .stroke(Color.yellow.opacity(Self.borderOpacity), lineWidth: UIMetrics.BorderWidth.hairline)
        }
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
        case .showcase: showcaseEntry
        case .appStoreConnect: appStoreConnectEntry
        case .googlePlay: googlePlayEntry
        case .iCloud: iCloudEntry
        case .automation: automationEntry
        case .settings: settingsEntry
        case .proFeatures: proFeaturesEntry
        case .tips: tipsEntry
        case .support: supportEntry
        // Rendered by ShortcutsHelp, which doesn't go through HelpEntry.
        case .shortcuts: HelpEntry(title: title, subtitle: nil, blocks: [])
        }
    }

    private var supportEntry: HelpEntry {
        let supportEmail = "leskiv.taras@gmail.com"
        return HelpEntry(
            title: "Support & Feedback",
            subtitle: "We read every message.",
            blocks: [
                .heading("Get in touch"),
                .bullet("Email: \(supportEmail)"),
                .bullet("Website: [screenshotbro.app](https://screenshotbro.app)"),
                .heading("When reporting a bug"),
                .paragraph("To help us reproduce, please include:"),
                .bullet("**Settings ▸ General ▸ Copy Diagnostics**, pasted into the email — it carries your version, setup, and the ID that lets us find your crash reports. No project content."),
                .bullet("Steps to reproduce, ideally with a screen recording."),
                .bullet("If the issue affects a project, use **Settings ▸ General ▸ Storage ▸ Create Backup…** and attach the resulting backup so we can reproduce on the exact data."),
                .heading("Legal"),
                .bullet("[Privacy Policy](https://screenshotbro.app/privacy)"),
                .bullet("[Terms of Service](https://screenshotbro.app/terms)"),
                .tip("Loved the app? An App Store review helps tremendously and keeps Screenshot Bro independent."),
            ]
        )
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
                .bullet("2. Drop your raw device screenshots onto templates or rows — Screenshot Bro fills them in order and detects device category/frame where possible."),
                .bullet("3. Pick a device frame, add a headline, choose a background, and arrange shapes."),
                .bullet("4. Add languages you support — translate text once and let the layout follow."),
                .bullet("5. Export. You'll get a folder organized by language and device, ready to upload."),
                .tip("If this is your first time, an interactive tour walks you through the editor when your first project opens. Pick a new project from a template any time via **File ▸ New Project**."),
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
                .bullet("Project order can be set to **By creation date** or **Alphabetically** in Settings ▸ General."),
                .heading("Renaming, duplicating, deleting"),
                .bullet("Right-click a project in the picker for rename, duplicate, and delete actions."),
                .bullet("Deleted projects are kept as **tombstones** for 30 days so iCloud sync can resolve conflicts cleanly. After 30 days the tombstone (and all images) are purged."),
                .heading("Where projects live on disk"),
                .bullet("`~/Library/Application Support/screenshot/projects.json` — index of all projects."),
                .bullet("`~/Library/Application Support/screenshot/projects/<uuid>/project.json` — project data."),
                .bullet("`~/Library/Application Support/screenshot/projects/<uuid>/resources/` — imported images, screenshots, and SVGs."),
                .tip("Projects autosave 0.3 seconds after the last change. You don't need to manually save. To make a one-off backup, use **Settings ▸ General ▸ Storage ▸ Create Backup…**."),
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
                .bullet("Choose a device category: **iPhone**, **iPad Pro 11\"**, **iPad Pro 13\"**, **MacBook**, **Android Phone**, **Abstract Pixel 9**, **Android Tablet**, or **Invisible** (an abstract layout with no visible frame)."),
                .bullet("Each category sets the row's default screenshot pixel size to a value the relevant store accepts."),
                .heading("Row inspector"),
                .bullet("Select a row (click empty canvas space inside it) to reveal row-level controls in the inspector."),
                .bullet("**Row label** — names the folder this row exports into."),
                .bullet("**Screenshot size presets** — quickly switch between supported store resolutions."),
                .bullet("**Background editor** — color, gradient, or image. See the **Backgrounds** topic."),
                .bullet("**Spanning background** — when on, the background spans the entire row width across all templates. When off, every template paints the same background independently."),
                .bullet("**Visibility** — hide a whole shape type (all text, all devices, all SVGs…) in this row. Hidden types are left out of the **export** too, not just the editor. **Borders** draws the divider lines between templates and is editor-only."),
                .heading("Edit and preview"),
                .bullet("The **pencil / eye** switch in the row header flips the row between editing and preview."),
                .bullet("Preview drops every handle, guide, and divider and lays the templates out as separate rounded tiles with a gap — the way a store listing shows them."),
                .heading("The row menu"),
                .bullet("**Add Screenshot** and **Add Element** — add a template column or a shape without leaving the header."),
                .bullet("**Duplicate Row**, **Add New Row Above / Below**, **Move Row Up / Down**."),
                .bullet("**Export Row** — Screenshots, Continuous, or Showcase, for this row alone."),
                .bullet("**Devices** — show or hide all frames, **Center All** of them, **Change All To** another model in one step, or **Reset All Images** to clear their screenshots."),
                .bullet("**Delete all** removes every shape of one type. **Reset Row** empties the row; **Delete Row** removes it."),
                .heading("Reordering and deleting"),
                .bullet("Drag a row's header to reorder. Use **⌘D** to duplicate a selected row, or use the row header/menu actions."),
                .bullet("Delete rows from the row header or row menu. Settings ▸ General has a confirmation toggle."),
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
                .bullet("The **⋯ menu** offers per-template actions: **Quick Look**, **Save as PNG…**, move left / right, **Add Screenshot Before / After**, duplicate, and delete."),
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
                .bullet("The properties bar shows font, weight, size, color, horizontal and vertical alignment, line height, and letter spacing."),
                .bullet("**Rich text**: while editing, select part of the text and use the format bar for bold, italic, underline, strikethrough, a different size, or a different color — per run, inside one shape. **Clear formatting** returns the selection to the shape's base style."),
                .bullet("**Text background** turns a headline into a badge: pick **Solid**, **Pill**, **Outline**, or **Highlight**, then tune color, padding, corner radius, opacity, and an outline."),
                .bullet("**Copy Text Style** / **Paste Text Style** (right-click) carry a text shape's whole look onto another one."),
                .bullet("Text auto-grows vertically by default. Drag a side handle to fix the width and let it wrap."),
                .bullet("Custom fonts: choose **Pick custom font** from the text font picker."),
                .heading("Image"),
                .bullet("Click the image well in the properties bar to pick a file, or drag and drop directly onto the shape."),
                .bullet("Fill modes: **Fill** (crop to fit), **Fit** (letterbox), **Stretch** (distort), **Tile** (repeat). Tile mode unlocks spacing, offset, and scale controls."),
                .bullet("**Remove Background** (right-click) cuts the subject out of the image on your Mac — nothing is uploaded anywhere."),
                .bullet("**Restore Original Aspect Ratio** (right-click) undoes stretching by fitting the height to the current width."),
                .bullet("Add an outline, corner radius, or rotation from the properties bar."),
                .heading("Device"),
                .bullet("Device shapes render the screenshot inside a real device frame. Pick a category and model in the properties bar."),
                .bullet("**Drop a screenshot onto the device** to attach it. The image is automatically clipped to the screen area."),
                .bullet("Each model has color variants and (where applicable) a landscape variant."),
                .bullet("**Match Size to Other Devices** (right-click) resizes the row's other devices of the same category to match this one."),
                .bullet("**Invisible** category shows the screenshot with no bezel — useful for clipped or abstract designs."),
                .heading("SVG"),
                .bullet("Click **SVG** to import a vector file. Or paste raw SVG via the SVG paste dialog."),
                .bullet("SVGs render with a configurable color override and scale crisply at any export resolution."),
                .bullet("During resize, rendering is debounced for performance — release the mouse to see the final crisp output."),
                .heading("Common properties"),
                .bullet("**X**, **Y**, **W**, and **H** at the head of the properties bar set position and size by hand. X is measured from the left edge of the template the shape sits in. Every device except an invisible frame keeps its proportions, so typing a width adjusts the height to match."),
                .bullet("Color, opacity, rotation (in degrees, editable as text), border radius, outline (color + width), and **Clip to Frame** (clips anything that overflows the template)."),
                .bullet("**Drop shadow** — enable it in the properties bar and pick **Soft**, **Medium**, or **Strong**, or set color, radius, offset, and opacity by hand. It works on a multi-shape selection too."),
                .bullet("**Lock** (**⌘L**) freezes a shape: clicks and drags pass straight through it. A locked shape's only right-click item is **Unlock**."),
                .bullet("Z-order: **⌘⇧]** brings forward, **⌘⇧[** sends back."),
            ]
        )
    }

    private var devicesEntry: HelpEntry {
        HelpEntry(
            title: "Devices & Frames",
            subtitle: "Real device frames with accurate screen insets.",
            blocks: [
                .paragraph("Device frames wrap your screenshot in an authentic device bezel. Screenshot Bro ships pixel-accurate frames for iPhone, iPad, Mac, Apple Watch, and Android-style layouts."),
                .heading("Categories"),
                .bullet("**iPhone** — iPhone 17, iPhone Air, iPhone 17 Pro, iPhone 17 Pro Max, and 3D iPhone options."),
                .bullet("**iPad Pro 11\"** and **iPad Pro 13\"** — current generation with portrait and landscape."),
                .bullet("**Mac** — MacBook Air 13\", MacBook Pro 14\", MacBook Pro 16\", and iMac 24\"."),
                .bullet("**Android Phone**, **Abstract Pixel 9**, and **Android Tablet** — abstract frames that flex to match the aspect ratio of dropped screenshots."),
                .bullet("**Watch** — Apple Watch Ultra 3 frame variants."),
                .bullet("**Invisible** — no visible bezel, just the screenshot. Useful for clipped layouts or abstract designs."),
                .heading("Picking a model and color"),
                .bullet("With a device shape selected, click the device thumbnail in the properties bar to open the picker."),
                .bullet("Models are grouped by category. Each shows available colors as small swatches."),
                .bullet("Switching color preserves the screenshot and any rotation."),
                .heading("Landscape mode"),
                .bullet("Concrete frames with portrait and landscape variants switch to the matching orientation when Screenshot Bro can infer it from a dropped screenshot."),
                .bullet("Use the orientation control for supported frames, or the rotation control to rotate the entire shape including frame and screen content."),
                .heading("3D device models (Beta)"),
                .bullet("Models marked **(3D)** — iPhone 17 and iPhone 17 Pro Max — are rendered from real geometry rather than a flat bezel image."),
                .bullet("Their **Appearance** popover in the properties bar adds **Pitch** and **Yaw** rotation, a **Matte** or **Glossy** finish, and **Ambient** / **Key** / **Rim** lighting."),
                .bullet("**Reset all** returns rotation, material, and lighting to their defaults."),
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
                .heading("Align, distribute, match"),
                .bullet("Right-click a multi-shape selection ▸ **Align Selected** for left / center / right, top / middle / bottom, plus **Distribute Horizontally** and **Distribute Vertically**."),
                .bullet("**Match to This** copies the shape you right-clicked — its **Position**, its **Size**, or both — onto the rest of the selection."),
                .bullet("**Center** places a shape vertically, horizontally, or at the exact center of its screenshot."),
                .bullet("**Duplicate ▸ To All Screenshots on the Left / Right / All** copies a shape into the other templates in the row at the same relative spot — the quickest way to repeat a logo or a footer."),
                .heading("Locking"),
                .bullet("**⌘L** locks or unlocks the selection. Locked shapes can't be dragged, resized, or deleted, and clicks fall through to whatever is behind them."),
                .bullet("Right-click a locked shape and choose **Unlock** to get it back."),
                .heading("Nudge"),
                .bullet("Arrow keys nudge the selection by 1px."),
                .bullet("**⇧ + Arrow** nudges by 10px."),
                .heading("Pan & zoom"),
                .bullet("Scroll vertically to navigate rows."),
                .bullet("Hold the **middle mouse button** and drag to pan."),
                .bullet("**⌘+** / **⌘−** zoom in/out, **⌘0** resets to the default zoom, **F** focuses on the current selection."),
                .bullet("Trackpad pinch and **⌘ + Scroll** also zoom on macOS."),
                .bullet("The toolbar zoom control ranges from 25% to 300% in 25% steps, with Fit and Actual Size actions in the popover."),
                .tip("If a shape spans across templates and you only see part of it, that's expected — each template clips shapes to its own bounds. Switch to a different template view or use **F** to focus on the whole shape."),
            ]
        )
    }

    private var localesEntry: HelpEntry {
        HelpEntry(
            title: "Languages & Translations",
            subtitle: "Translate text once, lay it out once, ship every language.",
            blocks: [
                .paragraph("Languages let you generate localized screenshot sets without duplicating your project. Each language shares the same shape set and can keep its own text, text styling, image assignments, and layout adjustments where a translation needs more space."),
                .heading("Adding languages"),
                .bullet("Open the **Language** menu in the toolbar, or use **Language ▸ Manage Languages…** in the menu bar."),
                .bullet("Pick from the built-in language presets, or define a custom code."),
                .bullet("The first language you add is the **base language** — the one whose text is the source of truth."),
                .heading("Switching the active language"),
                .bullet("**⌘]** / **⌘[** cycle forward / backward through languages."),
                .bullet("**⌘⌥0** jumps back to the base language."),
                .bullet("When editing a non-base language, a banner appears at the top of the canvas reminding you which language you're in."),
                .heading("How translations work"),
                .bullet("In a non-base language, edits are saved as **per-language overrides** — they don't change the base language."),
                .bullet("Text content and styling, image replacements, and position/size adjustments can differ by language. Shared properties such as colors and device choices are edited in the base language."),
                .bullet("If a language has no override for a shape, it falls back to the base language's content."),
                .heading("Translation helpers"),
                .bullet("**Auto-Translate Missing Text** — fills in text shapes that don't yet have an override for the current language."),
                .bullet("**Re-Translate All Text…** — replaces every existing override with a fresh translation. Use after editing the base language's text."),
                .bullet("**Translate Selected to All Languages** — appears in the language bar when editing the base language with text shapes selected. Translates the selection into every other language at once."),
                .bullet("**Revert to Base Language…** — drops all overrides for the current language, falling back to base text everywhere."),
                .bullet("**Edit Translation Table…** — open a side-by-side editor showing every text shape with its base content and per-language overrides."),
                .bullet("**Reuse Translation** (right-click a text shape) links it to another string, so both share one base text and one set of translations. A headline repeated across templates is then translated once."),
                .bullet("Right-click ▸ **Localization** translates just that shape into the current language or into all of them, or resets its translations."),
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
                .bullet("**Batch import**: drop multiple screenshots onto a row. Screenshot Bro fills existing device shapes in template order, then appends templates as needed."),
                .bullet("Recognized screenshot dimensions are used to pick an appropriate device category or frame when possible."),
                .heading("Background images"),
                .bullet("Drop directly into the background image well in the inspector, or pick via the file dialog."),
                .bullet("Both raster and SVG images are supported as backgrounds."),
                .heading("SVG paste"),
                .bullet("Use the **SVG** button in the shape toolbar to open the paste dialog."),
                .bullet("Paste SVG markup directly. Width and height are auto-detected; you can override them."),
                .bullet("SVGs are sanitized — script and event handlers are stripped before rendering."),
                .heading("Custom fonts"),
                .bullet("Open a text shape's font picker and choose **Pick custom font** to import `.otf` / `.ttf` files or a folder of font variants."),
                .bullet("Imported fonts are bundled with the project so they survive iCloud sync and project transfer."),
                .bullet("Fonts appear in the text shape font picker once registered."),
                .tip("Dropping a folder or a group of image files onto a row is the fastest way to fill a screenshot set in order."),
            ]
        )
    }

    private var exportingEntry: HelpEntry {
        HelpEntry(
            title: "Exporting",
            subtitle: "Produce store-ready PNGs and JPEGs.",
            blocks: [
                .heading("Quick export"),
                .bullet("Click **Export** in the toolbar, or press **⌘E**, to render the current project to the remembered export folder. If no folder is set, Screenshot Bro asks you to choose one."),
                .bullet("Use the export menu for **Export All Screenshots to Folder…**, row exports, per-language exports, and direct upload to **App Store Connect** or **Google Play**."),
                .bullet("File names are zero-padded (`01_…`, `02_…`) so they sort correctly when uploaded."),
                .heading("Three ways to render a row"),
                .bullet("**Screenshots** — one image per template. This is what the stores want."),
                .bullet("**Continuous** — the whole row as one wide image, templates side by side."),
                .bullet("**Showcase** — a marketing composition of the row on a styled background. See **Showcase Export**."),
                .bullet("All three are in the export menu (for every row) and in a row's **Export Row** menu (for that row alone)."),
                .heading("What actually gets exported"),
                .bullet("Only what you see. Shape types switched off in the inspector's **Visibility** section are left out of the exported image too."),
                .bullet("Template borders, alignment guides, and selection handles are editor-only and never exported."),
                .heading("Format and naming"),
                .bullet("**Settings ▸ Export ▸ Format**: PNG or JPEG. PNG is recommended for marketing screenshots."),
                .bullet("**Custom filename suffix**: add a suffix to every exported screenshot filename."),
                .bullet("Exports use the row's exact pixel dimensions so App Store and Google Play sizes stay correct."),
                .heading("Folder structure"),
                .bullet("With one language and one row: a flat folder of templates."),
                .bullet("With multiple languages: a top-level folder per language."),
                .bullet("With multiple rows: a sub-folder per row label (e.g. `iPhone 6.9\"`, `iPad 13\"`)."),
                .bullet("This mirrors the upload flow expected by App Store Connect's localized screenshot uploader."),
                .heading("Export folder memory"),
                .bullet("Set **Settings ▸ Export ▸ Export folder** to make **⌘E** export directly without prompting."),
                .bullet("Toggle **Reveal in Finder after export** in Settings to auto-reveal the result."),
                .heading("Preview vs export"),
                .bullet("The **pencil / eye** switch in a row header lays the row out as a store-style carousel with no editing chrome — the fastest check that a set reads well together."),
                .bullet("Use the **Quick Look** button in the template control bar to preview fully rendered screenshots without going through the export flow."),
                .bullet("Editor and export must always match exactly. If they don't, please report it as a bug."),
            ]
        )
    }

    private var showcaseEntry: HelpEntry {
        HelpEntry(
            title: "Showcase Export",
            subtitle: "Turn a row of screenshots into one marketing image.",
            blocks: [
                .paragraph("A showcase arranges a row's screenshots side by side on a styled background and renders them as a single image — for a product page, a launch post, a README, or an ad. It doesn't replace store screenshots; it's the picture you post *about* them."),
                .heading("Opening it"),
                .bullet("Export menu ▸ **Export Rows ▸ Showcase** for the whole project, or a row menu ▸ **Export Row ▸ Showcase** for one row."),
                .bullet("The sheet previews the result live as you change settings."),
                .heading("Shape and size"),
                .bullet("**Aspect ratio** presets: **Social** (1.91:1), **Square**, **Portrait** (4:5), **Story** (9:16), **YouTube** (16:9), and **Pinterest** (2:3)."),
                .bullet("**Output size**: Original, X-Large (4000 px), Large (2400 px), Medium (1600 px), or Small (1200 px) on the longest edge."),
                .bullet("**Spacing**, **Padding**, and **Corner radius** are percentages of the canvas, so a layout keeps its proportions at every output size."),
                .heading("Background"),
                .bullet("The same editor as a row background: color, gradient, or image, with every fill mode. See **Backgrounds**."),
                .tip("Export the same row twice — once as **Story** for a 9:16 post and once as **Social** for the link preview. The layout adapts to each aspect ratio instead of being cropped."),
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
                .bullet("Create a key with permission to edit app metadata. Account Holder, Admin, or App Manager roles are typical for screenshot uploads. Download the `.p8` private key file (you can only download it once)."),
                .bullet("Note the **Issuer ID** and **Key ID**."),
                .bullet("In Screenshot Bro: **Settings ▸ App Store Connect**, paste the Issuer ID and Key ID, import the `.p8` file, then run **Test Connection**."),
                .heading("Uploading screenshots"),
                .bullet("Click **Upload to App Store Connect…** from the export menu. Screenshot Bro renders the selected screenshots directly from the project."),
                .bullet("Pick the app and a version, then choose which rows go to which display type and locale."),
                .bullet("**Review Changes** lists, per locale and display type, exactly what will be added, what will be replaced, and what stays untouched. Nothing is sent to Apple until you confirm there."),
                .bullet("Sets are grouped by version and device — open a locale to compare the current App Store screenshots with the proposed ones. Locales that already match are hidden behind **Show unchanged**, and **Select All Changed** / **Deselect All** set what gets synced."),
                .heading("Editing store metadata"),
                .bullet("The same wizard edits the version's text, locale by locale, with a live character counter against Apple's limits."),
                .bullet("**App Info** (shared across versions): **App Name**, **Subtitle**, **Privacy Policy URL**."),
                .bullet("**This Version**: **What's New**, **Promotional Text**, **Description**, **Keywords**, **Support URL**, and the **Copyright** line."),
                .bullet("**Copy to all locales** fills every other language's *What's New* from the one you just wrote — useful before you translate it properly."),
                .heading("Demo mode"),
                .bullet("**Settings ▸ App Store Connect ▸ Demo mode** walks the whole flow against sample data — no API key needed, and nothing is ever sent to Apple."),
                .bullet("While demo mode is on, the real API key above it is ignored."),
                .tip("App Store Connect accepts 1–10 screenshots per display type and locale — one is enough to submit, though most apps use three or more. Screenshot Bro respects template ordering when uploading."),
            ]
        )
    }

    private var googlePlayEntry: HelpEntry {
        HelpEntry(
            title: "Google Play",
            subtitle: "Upload store listing screenshots to Google Play.",
            blocks: [
                .paragraph("Connect a Google Play service account once and Screenshot Bro can upload exported screenshots to your app's store listing without leaving the app."),
                .heading("Set up a service account"),
                .bullet("In the **Google Cloud console**, create a service account and enable the **Google Play Android Developer API**."),
                .bullet("Create a **JSON key** for that service account and download it — this is the file Screenshot Bro imports."),
                .bullet("In the **Play Console ▸ Users and permissions**, invite the service account's email and grant it access to edit your app's store listing."),
                .bullet("In Screenshot Bro: **Settings ▸ Google Play**, click **Import .json File…**, then run **Test Connection**. The key is stored in your Mac's Keychain."),
                .heading("Uploading"),
                .bullet("Choose **Upload to Google Play…** from the export menu. Screenshot Bro renders the selected screenshots directly from the project."),
                .bullet("Enter your app's **package name** (for example `com.example.myapp`), then review which screenshots go to which language before confirming."),
                .bullet("The upload is staged as a Play **edit** and committed when you confirm. Google Play accepts at most 8 screenshots per type."),
                .heading("Demo mode"),
                .bullet("**Settings ▸ Google Play ▸ Demo mode** runs a simulated upload — no service account required and nothing is ever sent to Google Play."),
                .bullet("Use it to walk through the whole upload flow before you have credentials set up. While demo mode is on, the imported service account is ignored."),
                .tip("Google Play enforces stricter screenshot aspect-ratio and dimension limits than the App Store. The default 1242×2688 iPhone size is too tall for Play — if an upload is rejected, switch the row to a screenshot-size preset Play accepts."),
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
                .bullet("The Projects screen shows sync progress while iCloud is uploading or downloading."),
                .bullet("Behind the scenes, an `NSMetadataQuery` watches each project for upload/download progress."),
                .tip("If sync seems stuck, open Finder ▸ iCloud Drive ▸ Screenshot Bro and check whether files are still uploading. Toggling iCloud off and on again forces a re-scan."),
            ]
        )
    }

    private var automationEntry: HelpEntry {
        HelpEntry(
            title: "Automation & MCP",
            subtitle: "Let an AI assistant build screenshots for you.",
            blocks: [
                .paragraph("Screenshot Bro can host a local **MCP server** — a small server running only on your Mac that AI assistants and MCP clients (such as Claude Code, Claude Desktop, or Cursor) connect to. Once connected, the assistant can create and edit projects, arrange shapes, translate text, and export screenshots on your behalf, driving the app while you watch."),
                .heading("Turning it on"),
                .bullet("**Settings ▸ Automation ▸ Enable MCP server.** It's off by default."),
                .bullet("The server runs on `127.0.0.1` (loopback only) — it is not reachable from other computers or the internet."),
                .bullet("Once enabled it stays on and starts automatically the next time you launch. The app has to be running for a client to connect."),
                .heading("Connecting an assistant"),
                .bullet("The easiest way: click **Copy Agent Prompt** and paste it into your AI assistant. It contains everything the assistant needs to add the server itself, then reconnect."),
                .bullet("Prefer to configure by hand? Use **Copy Configuration (JSON)** for a standard `mcpServers` entry, or copy the **Server URL** and **Access Token** individually and add them in your client."),
                .bullet("The **Status** row shows whether the server is running and on which port."),
                .heading("What the assistant can do"),
                .bullet("Create projects (including from bundled templates), rename, delete, and switch between them."),
                .bullet("Add, edit, move, and remove rows, template columns, and shapes."),
                .bullet("Import screenshots into device frames, add and translate languages, and set per-language text."),
                .bullet("**Render a preview** so it can actually see the current canvas, and **export** the finished screenshots."),
                .bullet("Read and rewrite your **App Store Connect descriptions**, and preview then apply a **screenshot sync** to a version."),
                .bullet("Everything goes through the same actions you use by hand — so the assistant's changes are undoable with **⌘Z** and autosaved like any other edit."),
                .heading("Security & the access token"),
                .bullet("The server requires an **access token**: every request must present it, so another app on your Mac can't quietly drive Screenshot Bro."),
                .bullet("Keep the token private — anyone who has it can control the app while the server is running."),
                .bullet("**Regenerate Access Token** issues a fresh token and restarts the server; any client using the old token must be updated."),
                .tip("If the server won't start, something else is usually holding its port — quit that program, then switch the server off and on again. Turning it off releases the port immediately."),
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
                .bullet("**Default device frame** — pre-selects a device category and model for new rows."),
                .bullet("**Screenshots per new row** — number of empty templates a new row starts with."),
                .bullet("**Default zoom** — initial zoom level when opening the app."),
                .bullet("**Ask before deleting rows and screenshots** — show a confirmation prompt for destructive row and screenshot actions."),
                .bullet("**Project order** — By creation date or Alphabetically."),
                .bullet("**iCloud sync** — toggle and check status."),
                .bullet("**Storage** — open the project library in Finder or create a one-off backup zip."),
                .bullet("**Version** — the build you're running. Worth quoting in a bug report."),
                .heading("Export"),
                .bullet("**Format** — PNG or JPEG."),
                .bullet("**Custom filename suffix** — append a suffix to exported screenshot filenames."),
                .bullet("**Reveal in Finder after export** — auto-reveal results in Finder."),
                .bullet("**Export folder** — choose or clear the folder Screenshot Bro reuses for **⌘E**."),
                .heading("App Store Connect"),
                .bullet("API key (Issuer ID, Key ID, `.p8` file), **Test Connection**, and **Demo mode**. See the App Store Connect topic."),
                .heading("Google Play"),
                .bullet("Import a service account JSON key, test the connection, and toggle demo mode. See the Google Play topic."),
                .heading("Automation"),
                .bullet("Enable the local MCP server and copy the agent prompt, connection JSON, or access token. See the Automation & MCP topic."),
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
                .bullet("No row or screenshot-column limits when building larger launch sets."),
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
                .bullet("**Drop groups of screenshots together.** Select several image files and drop them onto a row — Screenshot Bro fills templates in order and detects device category/frame where possible."),
                .bullet("**Span backgrounds for storytelling.** Turn on row spanning and use a wide gradient or panoramic image to make a 3-template carousel feel like one continuous scene."),
                .bullet("**Lock aspect when resizing icons** by holding **⇧** while dragging a corner handle."),
                .bullet("**Duplicate while dragging** with **⌥**. Combined with snap, this is the fastest way to lay out a row of equal-sized cards."),
                .bullet("**Type rotation degrees directly.** The rotation field accepts text input — type `45` for an exact 45° rotation instead of dragging."),
                .bullet("**Use the SVG button for icons.** SVG scales infinitely, so your hero icon stays crisp at export size."),
                .bullet("**Re-translate after editing base text.** If you change the base headline, run **Language ▸ Re-Translate All Text…** (or use **Translate Selected to All Languages** in the language bar with the edited text selected) so every language picks up the new wording."),
                .bullet("**Use Invisible category for clipped designs.** When you want the screenshot to bleed off the canvas with no bezel, pick the Invisible device category."),
                .bullet("**Pin frequently used projects.** Right-click in the project picker to pin and keep them at the top."),
                .bullet("**Preview before exporting.** The Quick Look button on each template renders the row's screenshots and opens the preview at that template — handy for spot-checks."),
                .bullet("**Custom fonts persist.** Imported fonts are bundled per project, so a project shared via iCloud or zip backup keeps its typography."),
                .bullet("**Repeat a shape across the row.** Right-click ▸ **Duplicate ▸ To All Screenshots** drops a logo or footer onto every template at the same spot."),
                .bullet("**Translate a repeated headline once.** Right-click a text shape ▸ **Reuse Translation** links it to another string so they share one translation."),
                .bullet("**Lock the background art.** **⌘L** on a full-bleed image stops you grabbing it every time you click near the canvas edge."),
                .bullet("**Check the set, not just the screenshot.** The pencil/eye switch in a row header shows the templates as a store-style carousel, which is how buyers will actually see them."),
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
            ("⌘N", "New project"),
            ("⌘E", "Export screenshots")
        ]),
        Group(title: "Edit", rows: [
            ("⌘Z", "Undo"),
            ("⌘⇧Z", "Redo"),
            ("⌘C", "Copy selected shapes, or focused text"),
            ("⌘X", "Cut focused text"),
            ("⌘V", "Paste shapes, images, SVGs, or focused text"),
            ("⌘A", "Select all shapes in the active row, or focused text"),
            ("⌘D", "Duplicate selected shapes / row"),
            ("⌘L", "Lock or unlock selected shapes"),
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
            ("⌘0", "Reset to default zoom"),
            ("⌘⌥I", "Show or hide the inspector"),
            ("F", "Focus on selection"),
            ("Pinch / ⌘ + Scroll", "Zoom canvas"),
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
        Group(title: "App", rows: [
            ("⌘,", "Open Settings"),
            ("⌘?", "Open Screenshot Bro Help"),
        ]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HelpHeader("Keyboard Shortcuts", subtitle: "Mac keyboard shortcuts and canvas gestures.")
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
#endif
