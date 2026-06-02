import SwiftUI
import UniformTypeIdentifiers

struct TemplateControlBar: View {
    @Environment(AppState.self) private var state
    @Binding var template: ScreenshotTemplate
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
    var onDropBackgroundImage: ((NSImage) -> Void)? = nil
    var onDropBackgroundSvg: ((String) -> Void)? = nil
    var onDuplicate: () -> Void = {}
    var onDuplicateToEnd: () -> Void = {}
    var onInsertBefore: () -> Void = {}
    var onInsertAfter: () -> Void = {}
    var onDelete: () -> Void
    var onLoadFullResImages: (() -> [String: NSImage])? = nil
    @AppStorage("confirmBeforeDeleting") private var confirmBeforeDeleting = true
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
        template.backgroundImageConfig.fileName.flatMap { screenshotImages[$0] }
    }
    private var isImageBackgroundMissing: Bool {
        template.overrideBackground &&
        template.backgroundStyle == .image &&
        backgroundPreviewImage == nil
    }

    /// Routes per-template background writes through `updateRowContinuous` so a drag
    /// burst (gradient stops/angle/center, image sliders) collapses into a single
    /// undo entry instead of one full-row snapshot per tick.
    private func continuousTemplateBinding<T>(_ keyPath: WritableKeyPath<ScreenshotTemplate, T>) -> Binding<T> {
        Binding(
            get: {
                if state.continuousRowEditId == row.id,
                   let workingRow = state.continuousRowEditWorkingRow,
                   index < workingRow.templates.count {
                    return workingRow.templates[index][keyPath: keyPath]
                }
                return template[keyPath: keyPath]
            },
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
        return template.overrideBackground
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
                ActionButton(icon: "arrow.down.circle", tooltip: "Download") {
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
                        if template.overrideBackground {
                            if template.backgroundStyle == .image {
                                if let image = backgroundPreviewImage {
                                    Image(nsImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 12, height: 12)
                                        .clipShape(RoundedRectangle(cornerRadius: 2))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 2)
                                                .strokeBorder(.secondary.opacity(0.5), lineWidth: UIMetrics.BorderWidth.hairline)
                                        )
                                } else {
                                    Image(systemName: "photo.badge.plus")
                                        .font(.system(size: UIMetrics.FontSize.numericBadge))
                                        .frame(width: 12, height: 12)
                                }
                            } else {
                                template.backgroundFillView()
                                    .frame(width: 12, height: 12)
                                    .clipShape(RoundedRectangle(cornerRadius: 2))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 2)
                                            .strokeBorder(.secondary.opacity(0.5), lineWidth: UIMetrics.BorderWidth.hairline)
                                    )
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
                .sheet(isPresented: $showBackgroundPopover) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Background Override")
                                .font(.headline)
                            Spacer()
                            Button {
                                showBackgroundPopover = false
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                        }

                        Toggle(
                            "Override background",
                            isOn: $template.overrideBackground.onSet { onSave() }
                        )
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .font(.system(size: UIMetrics.FontSize.body))

                        if template.overrideBackground {
                            BackgroundEditor(
                                backgroundStyle: $template.backgroundStyle,
                                bgColor: $template.bgColor,
                                gradientConfig: continuousTemplateBinding(\.gradientConfig),
                                backgroundImageConfig: continuousTemplateBinding(\.backgroundImageConfig),
                                backgroundImage: backgroundPreviewImage,
                                onChanged: onSave,
                                onPickImage: onPickBackgroundImage,
                                onRemoveImage: onRemoveBackgroundImage,
                                onDropImage: onDropBackgroundImage,
                                onDropSvg: onDropBackgroundSvg
                            )

                            if template.backgroundStyle != .color {
                                HStack(spacing: 4) {
                                    Text("Blur")
                                        .font(.system(size: UIMetrics.FontSize.body))
                                    Spacer()
                                    Slider(
                                        value: $template.backgroundBlur.onSet { onSave() },
                                        in: 0...100
                                    )
                                    .frame(width: UIMetrics.SliderWidth.standard)
                                    Text("\(Int(template.backgroundBlur))")
                                        .font(.system(size: UIMetrics.FontSize.numericBadge).monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 38, alignment: .trailing)
                                }
                            }
                        }
                    }
                    .padding(20)
                    .frame(width: 320)
                    #if os(iOS)
                    .presentationSizing(.fitted)
                    .presentationDragIndicator(.visible)
                    #endif
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
                Button("Save as PNG...", systemImage: "square.and.arrow.down") {
                    downloadScreenshot()
                }
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
                Image(systemName: "ellipsis.circle")
                    #if os(macOS)
                    .font(.system(size: UIMetrics.FontSize.body))
                    #else
                    .font(.system(size: 20))
                    #endif
                    .frame(width: UIMetrics.ActionButton.frameSize, height: UIMetrics.ActionButton.frameSize)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
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

    private func confirmDeleteTemplate() {
        if confirmBeforeDeleting {
            isDeletingTemplate = true
        } else {
            onDelete()
        }
    }

    private func renderExportPNG() -> Data? {
        let images = onLoadFullResImages?() ?? screenshotImages
        return ExportService.renderTemplatePNG(index: index, row: row, screenshotImages: images, localeState: localeState)
    }

    private func previewScreenshot() {
        state.deselectAll()
        isPreviewing = true
        renderError = nil
        Task {
            defer { isPreviewing = false }
            let images = onLoadFullResImages?() ?? screenshotImages
            let rowBackground = ExportService.renderComposedBackgroundImage(
                row: row,
                screenshotImages: images,
                displayScale: 1.0,
                labelPrefix: "preview row"
            )
            let fontFamilies = Set(PlatformFonts.systemFamilyNames)
            var urls: [URL] = []
            for i in row.templates.indices {
                let image = ExportService.renderSingleTemplateImage(
                    index: i, row: row, screenshotImages: images,
                    localeCode: localeState.activeLocaleCode, localeState: localeState,
                    availableFontFamilies: fontFamilies,
                    preRenderedRowBackground: rowBackground
                )
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("screenshot-\(i + 1)-\(localeState.activeLocaleCode).png")
                do {
                    guard let pngData = await Task.detached(operation: { ExportService.opaquePNGData(from: image) }).value else {
                        renderError = String(localized: "Could not render screenshot for preview.")
                        return
                    }
                    try pngData.write(to: tempURL)
                    urls.append(tempURL)
                } catch {
                    renderError = String(localized: "Could not write preview file: \(error.localizedDescription)")
                    return
                }
            }
            QuickLookCoordinator.shared.preview(imagesAt: urls, startingAt: index)
        }
    }

    private func downloadScreenshot() {
        if let message = ExportService.savePNGDataViaPanel(
            defaultName: "screenshot-\(index + 1)",
            data: renderExportPNG
        ) {
            renderError = message
        }
    }
}
