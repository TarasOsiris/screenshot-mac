import SwiftUI
import UniformTypeIdentifiers

struct TemplateControlBar: View {
    private static let backgroundOverrideTitle: LocalizedStringKey = "Background Override"
    // macOS saves via panel; iPad presents the share sheet — same action, different affordance.
    #if os(macOS)
    private static let exportIcon = "arrow.down.circle"
    private static let exportTitle: LocalizedStringKey = "Download"
    #else
    private static let exportIcon = "square.and.arrow.up"
    private static let exportTitle: LocalizedStringKey = "Share…"
    #endif
    @Environment(AppState.self) private var state
    /// Read-only on purpose: every write goes through `continuousTemplateBinding`, so there is
    /// no second path that could land in `state.rows` behind the in-flight working row.
    let template: ScreenshotTemplate
    let row: ScreenshotRow
    let index: Int
    let zoom: CGFloat
    var screenshotImages: [String: NSImage] = [:]
    var localeState: LocaleState = .default
    var canMoveLeft: Bool = false
    var canMoveRight: Bool = false
    var onMoveLeft: () -> Void = {}
    var onMoveRight: () -> Void = {}
    var onSave: () -> Void
    var onPickBackgroundImage: (() -> Void)?
    var onRemoveBackgroundImage: (() -> Void)?
    var onDropBackgroundImage: ((NSImage) -> Void)?
    var onDropBackgroundSvg: ((String) -> Void)?
    var onDuplicate: () -> Void = {}
    var onDuplicateToEnd: () -> Void = {}
    var onInsertBefore: () -> Void = {}
    var onInsertAfter: () -> Void = {}
    var onDelete: () -> Void
    var onLoadFullResImages: (() -> [String: NSImage])?
    @AppStorage(AppSettingsKeys.confirmBeforeDeleting) private var confirmBeforeDeleting = AppSettingsKeys.Default.confirmBeforeDeleting
    @State private var isDeletingTemplate = false
    @State private var showBackgroundPopover = false
    @State private var renderError: String?
    @State private var isPreviewing = false

    private var canDelete: Bool { row.templates.count > 1 }

    // The bar is pinned to the (zoom-scaled) column width, so at low zoom it can get narrower
    // than its buttons — especially with the larger iPad touch targets. Collapse adaptively:
    // full → just preview/delete/menu → just the (complete) ellipsis menu.
    private enum BarDensity { case full, compact, minimal }
    private var density: BarDensity {
        let buttonW = UIMetrics.ActionButton.frameSize
        let spacing: CGFloat = 6
        let available = row.displayWidth(zoom: zoom) - 8 // horizontal padding (4 each side)
        func needed(_ count: Int) -> CGFloat {
            CGFloat(count) * buttonW + CGFloat(max(0, count - 1)) * spacing
        }
        let trailing = (canDelete ? 1 : 0) + 1 // trash + ellipsis
        if available >= needed(5 + trailing) { return .full }       // eye + download + left + right + bg
        if available >= needed(1 + trailing) { return .compact }    // eye + trash + ellipsis
        return .minimal                                             // ellipsis only
    }
    private var showsFullGroup: Bool { density == .full }
    private var showsPrimaryButtons: Bool { density != .minimal }
    private var backgroundPreviewImage: NSImage? {
        liveTemplate.backgroundImageConfig.fileName.flatMap { screenshotImages[$0] }
    }
    private var isImageBackgroundMissing: Bool {
        liveTemplate.overrideBackground &&
        liveTemplate.backgroundStyle == .image &&
        backgroundPreviewImage == nil
    }

    /// The template as the popover's controls see it: an in-flight continuous edit lives in the
    /// working row until the throttle writes it back, so reading `template` directly here would
    /// show (and re-submit) a value the user has already changed.
    private var liveTemplate: ScreenshotTemplate {
        if state.continuousRowEditId == row.id,
           let workingRow = state.edits.continuousRowEditWorkingRow,
           index < workingRow.templates.count {
            return workingRow.templates[index]
        }
        return template
    }

    /// Routes per-template background writes through `updateRowContinuous` so a drag
    /// burst (gradient stops/angle/center, image sliders) collapses into a single
    /// undo entry instead of one full-row snapshot per tick. Every control in the popover
    /// must use this: a direct `$template` write lands in `state.rows` while the working row
    /// still holds the old value, and the next throttle tick writes that stale row back over it.
    private func continuousTemplateBinding<T>(_ keyPath: WritableKeyPath<ScreenshotTemplate, T>) -> Binding<T> {
        Binding(
            get: { liveTemplate[keyPath: keyPath] },
            set: { newValue in
                let templateIndex = index
                state.updateRowContinuous(row.id, actionName: "Edit Template") { r in
                    guard templateIndex < r.templates.count else { return }
                    r.templates[templateIndex][keyPath: keyPath] = newValue
                }
            }
        )
    }
    private var backgroundButtonHelp: LocalizedStringKey {
        if isImageBackgroundMissing {
            return "Background override (image not selected)"
        }
        return "Background override"
    }
    private var backgroundButtonStyle: AnyShapeStyle {
        if isImageBackgroundMissing {
            return AnyShapeStyle(Color.orange)
        }
        return liveTemplate.overrideBackground
            ? AnyShapeStyle(.primary)
            : AnyShapeStyle(.secondary)
    }

    var body: some View {
        HStack(spacing: 6) {
            if showsPrimaryButtons {
                ActionButton(icon: "eye", tooltip: "Preview", disabled: isPreviewing) {
                    previewScreenshot()
                }
                .opacity(isPreviewing ? 0 : 1)
                .overlay {
                    if isPreviewing {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            if showsFullGroup {
                ActionButton(icon: Self.exportIcon, tooltip: Self.exportTitle) {
                    downloadScreenshot()
                }
                ActionButton(icon: "chevron.left", tooltip: "Move left", disabled: !canMoveLeft) {
                    onMoveLeft()
                }
                ActionButton(icon: "chevron.right", tooltip: "Move right", disabled: !canMoveRight) {
                    onMoveRight()
                }

                Button {
                    showBackgroundPopover = true
                } label: {
                    HStack(spacing: 3) {
                        if liveTemplate.overrideBackground {
                            let swatch = UIMetrics.ColorSwatch.overrideIndicator
                            if liveTemplate.backgroundStyle == .image {
                                if let image = backgroundPreviewImage {
                                    Image(nsImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: swatch, height: swatch)
                                        .clipShape(RoundedRectangle(cornerRadius: 2))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 2)
                                                .strokeBorder(.secondary.opacity(0.5), lineWidth: UIMetrics.BorderWidth.hairline)
                                        }
                                } else {
                                    Image(systemName: "photo.badge.plus")
                                        .font(.system(size: UIMetrics.ColorSwatch.overrideIndicatorIcon))
                                        .frame(width: swatch, height: swatch)
                                }
                            } else {
                                liveTemplate.backgroundFillView()
                                    .frame(width: swatch, height: swatch)
                                    .clipShape(RoundedRectangle(cornerRadius: 2))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 2)
                                            .strokeBorder(.secondary.opacity(0.5), lineWidth: UIMetrics.BorderWidth.hairline)
                                    }
                            }
                        } else {
                            Image(systemName: "paintbrush")
                                .font(.system(size: UIMetrics.ActionButton.iconSize))
                        }
                    }
                    .frame(width: UIMetrics.ActionButton.frameSize, height: UIMetrics.ActionButton.frameSize)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .focusable(false)
                .foregroundStyle(backgroundButtonStyle)
                .help(backgroundButtonHelp)
                // `.sheet` rather than the docked `.panel`: the panel needs a `BarPanelHost`,
                // which only `ShapePropertiesBar` provides.
                .barPopover(
                    isPresented: $showBackgroundPopover,
                    title: Self.backgroundOverrideTitle,
                    style: .sheet
                ) {
                    backgroundOverrideContent
                }
            }

            Spacer()
            if canDelete && showsPrimaryButtons {
                ActionButton(icon: "trash", tooltip: "Delete Screenshot", isDestructive: true) {
                    confirmDeleteTemplate()
                }
            }
            Menu {
                Button("Quick Look", systemImage: "eye") {
                    previewScreenshot()
                }
                .disabled(isPreviewing)
                #if os(macOS)
                Button("Save as PNG...", systemImage: "square.and.arrow.down") {
                    downloadScreenshot()
                }
                #else
                Button(Self.exportTitle, systemImage: Self.exportIcon) {
                    downloadScreenshot()
                }
                #endif
                Button("Move Left", systemImage: "chevron.left") {
                    onMoveLeft()
                }
                .disabled(!canMoveLeft)
                Button("Move Right", systemImage: "chevron.right") {
                    onMoveRight()
                }
                .disabled(!canMoveRight)
                Button("Add Screenshot Before", systemImage: "plus.rectangle.on.rectangle") {
                    onInsertBefore()
                }
                Button("Add Screenshot After", systemImage: "plus.rectangle.on.rectangle") {
                    onInsertAfter()
                }
                Menu("Duplicate Screenshot", systemImage: "plus.square.on.square") {
                    Button("Place After This One", systemImage: "plus.square.on.square") {
                        onDuplicate()
                    }
                    Button("Place at End", systemImage: "arrow.right.to.line") {
                        onDuplicateToEnd()
                    }
                }
                if canDelete {
                    Divider()
                    Button("Delete Screenshot", systemImage: "trash", role: .destructive) {
                        confirmDeleteTemplate()
                    }
                }
            } label: {
                Label("More actions", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
                    .font(.system(size: UIMetrics.ActionButton.iconSize))
                    .frame(width: UIMetrics.ActionButton.frameSize, height: UIMetrics.ActionButton.frameSize)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            #if !os(macOS)
            .tint(.secondary)
            #endif
            .help("More actions")
        }
        .controlSize(.small)
        .padding(.horizontal, 4)
        .frame(width: row.displayWidth(zoom: zoom))
        .overlay(alignment: .leading) {
            if index > 0 {
                Rectangle()
                    .fill(.separator)
                    .frame(width: UIMetrics.BorderWidth.standard, height: 20)
            }
        }
        .alert("Delete Screenshot", isPresented: $isDeletingTemplate) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this screenshot?")
        }
        .alert("Render Failed", isPresented: .init(
            get: { renderError != nil },
            set: { if !$0 { renderError = nil } }
        )) {
            Button("OK") { renderError = nil }
        } message: {
            Text(renderError ?? "")
        }
    }

    private var blurSlider: some View {
        let blur = continuousTemplateBinding(\.backgroundBlur)
        return PopoverSliderRow(
            label: "Blur",
            value: blur,
            range: 0...100,
            displayValue: "\(Int(blur.wrappedValue))"
        )
    }

    @ViewBuilder
    private var backgroundOverrideContent: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(Self.backgroundOverrideTitle)
                    .font(.headline)
                Spacer()
                Button {
                    showBackgroundPopover = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Close")
            }

            Toggle(
                "Override background",
                isOn: continuousTemplateBinding(\.overrideBackground)
            )
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(.system(size: UIMetrics.FontSize.body))

            if liveTemplate.overrideBackground {
                backgroundEditorContent

                if liveTemplate.backgroundStyle != .color {
                    blurSlider
                }
            }
        }
        .padding(20)
        .frame(width: 320)
        // Otherwise the system color panel taking key focus dismisses the popover mid-edit;
        // `onExitCommand` puts Esc back.
        .interactiveDismissDisabled()
        .onExitCommand { showBackgroundPopover = false }
        #else
        // A Form keeps the sheet at full detent height, so toggling the override doesn't
        // resize/re-center the floating iPad sheet around its content.
        Form {
            Section {
                Toggle(
                    "Override background",
                    isOn: continuousTemplateBinding(\.overrideBackground)
                )
            }
            if liveTemplate.overrideBackground {
                Section {
                    backgroundEditorContent
                }
                if liveTemplate.backgroundStyle != .color {
                    Section { blurSlider }
                }
            }
        }
        #endif
    }

    @ViewBuilder
    private var backgroundEditorContent: some View {
        BackgroundEditor(
            backgroundStyle: continuousTemplateBinding(\.backgroundStyle),
            bgColor: continuousTemplateBinding(\.bgColor),
            gradientConfig: continuousTemplateBinding(\.gradientConfig),
            backgroundImageConfig: continuousTemplateBinding(\.backgroundImageConfig),
            backgroundImage: backgroundPreviewImage,
            onChanged: onSave,
            onPickImage: onPickBackgroundImage,
            onRemoveImage: onRemoveBackgroundImage,
            onDropImage: onDropBackgroundImage,
            onDropSvg: onDropBackgroundSvg
        )
    }

    private func confirmDeleteTemplate() {
        if confirmBeforeDeleting {
            isDeletingTemplate = true
        } else {
            onDelete()
        }
    }

    /// Renders on the main actor, encodes off it — the deflate of a full-resolution
    /// template used to block the main thread for the whole save.
    private func renderExportPNG() async -> Data? {
        let images = onLoadFullResImages?() ?? screenshotImages
        let image = RowRenderer.renderSingleTemplateImage(
            index: index, row: row, screenshotImages: images,
            localeCode: localeState.activeLocaleCode, localeState: localeState,
            availableFontFamilies: state.availableFontFamilySet
        )
        return await ExportImageEncoder.opaquePNGDataOffMain(from: image)
    }

    private func previewScreenshot() {
        state.deselectAll()
        isPreviewing = true
        renderError = nil
        Task {
            defer { isPreviewing = false }
            let context = RowRenderContext(
                row: row,
                images: onLoadFullResImages?() ?? screenshotImages,
                localeCode: localeState.activeLocaleCode,
                localeState: localeState,
                availableFontFamilies: state.availableFontFamilySet,
                label: "preview row"
            )
            // A folder per preview, handed to QuickLook to delete on dismiss. Writing into the
            // bare temp directory left every preview's PNGs behind for the whole session.
            let folder: URL
            do {
                folder = try ExportService.makeTempExportFolder()
            } catch {
                renderError = String(localized: "Could not write preview file: \(error.localizedDescription)")
                return
            }
            var urls: [URL] = []
            for i in context.templateIndices {
                let image = context.templateImage(at: i)
                let tempURL = folder.appendingPathComponent("screenshot-\(i + 1)-\(localeState.activeLocaleCode).png")
                do {
                    guard let pngData = await ExportImageEncoder.opaquePNGDataOffMain(from: image) else {
                        try? FileManager.default.removeItem(at: folder)
                        renderError = String(localized: "Could not render screenshot for preview.")
                        return
                    }
                    try pngData.write(to: tempURL)
                    urls.append(tempURL)
                } catch {
                    try? FileManager.default.removeItem(at: folder)
                    renderError = String(localized: "Could not write preview file: \(error.localizedDescription)")
                    return
                }
            }
            QuickLookCoordinator.shared.preview(imagesAt: urls, startingAt: index, temporaryFolder: folder)
        }
    }

    private func downloadScreenshot() {
        Task {
            if let message = await ExportService.savePNGDataViaPanel(
                defaultName: "screenshot-\(index + 1)",
                data: renderExportPNG
            ) {
                renderError = message
            }
        }
    }
}
