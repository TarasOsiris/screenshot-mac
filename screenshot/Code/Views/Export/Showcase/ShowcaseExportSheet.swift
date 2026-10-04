import SwiftUI

enum ShowcaseExportSheetMetrics {
    static let minWidth: CGFloat = 920
    static let idealWidth: CGFloat = 1180
    static let maxWidth: CGFloat = 1600
    static let minHeight: CGFloat = 640
    static let idealHeight: CGFloat = 800
    static let maxHeight: CGFloat = 1200
    static let settingsPanelWidth: CGFloat = 320
    static let footerHeight: CGFloat = 56
    static let previewContentInset: CGFloat = 24
    static let previewItemSpacing: CGFloat = 24
    /// Vertical budget reserved for a row's caption (label + dimensions) above its preview.
    static let previewCaptionHeight: CGFloat = 24
    /// Multi-row grid switches to two columns when the available width crosses this point.
    static let gridTwoColumnThreshold: CGFloat = 720
}

struct ShowcaseExportSheet: View {
    let candidateRows: [ScreenshotRow]
    let loadImages: (ScreenshotRow) -> [String: NSImage]
    let localeCode: String?
    let localeState: LocaleState
    let availableFontFamilies: Set<String>
    var onExport: (ShowcaseExportConfig, NSImage?, Set<UUID>, Set<UUID>, ExportDestination) -> Void

    #if os(macOS)
    @Environment(\.dismiss) private var dismiss
    #else
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var config = ShowcaseExportConfig()
    @State private var backgroundImage: NSImage?
    @State private var selectedRowIds: Set<UUID>
    @State private var excludedTemplateIds: Set<UUID> = []
    @State private var showingResetConfirmation = false

    init(
        candidateRows: [ScreenshotRow],
        loadImages: @escaping (ScreenshotRow) -> [String: NSImage],
        localeCode: String?,
        localeState: LocaleState,
        availableFontFamilies: Set<String>,
        onExport: @escaping (ShowcaseExportConfig, NSImage?, Set<UUID>, Set<UUID>, ExportDestination) -> Void
    ) {
        self.candidateRows = candidateRows
        self.loadImages = loadImages
        self.localeCode = localeCode
        self.localeState = localeState
        self.availableFontFamilies = availableFontFamilies
        self.onExport = onExport
        _selectedRowIds = State(initialValue: Set(candidateRows.map(\.id)))
    }

    private var transientBackgroundImages: [String: NSImage] {
        backgroundImage.map { [ShowcaseExportConfig.transientBackgroundKey: $0] } ?? [:]
    }

    private var selection: ShowcaseExportSelection {
        ShowcaseExportSelection(
            candidateRows: candidateRows,
            selectedRowIds: selectedRowIds,
            excludedTemplateIds: excludedTemplateIds
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            mainLayout
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            #if os(macOS)
            Divider()

            footer
                .frame(height: ShowcaseExportSheetMetrics.footerHeight)
                .frame(maxWidth: .infinity)
            #endif
        }
        #if os(macOS)
        .frame(
            minWidth: ShowcaseExportSheetMetrics.minWidth,
            idealWidth: ShowcaseExportSheetMetrics.idealWidth,
            maxWidth: ShowcaseExportSheetMetrics.maxWidth,
            minHeight: ShowcaseExportSheetMetrics.minHeight,
            idealHeight: ShowcaseExportSheetMetrics.idealHeight,
            maxHeight: ShowcaseExportSheetMetrics.maxHeight
        )
        #else
        .iosSheetChrome(
            Text("Showcase Export"),
            confirmTitle: Text("Export…"),
            confirmSystemImage: "square.and.arrow.up",
            confirmDisabled: selection.selectedRowsOrdered.isEmpty,
            showsCancel: true,
            confirmMenu: { exportDestinationMenu }
        )
        #endif
        .alert("Reset Showcase Settings?", isPresented: $showingResetConfirmation) {
            Button("Reset", role: .destructive) {
                resetShowcaseSettings()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Format, background, layout, and excluded screenshots will return to defaults. Row selection is preserved.")
        }
    }

    // MARK: - Adaptive layout

    /// Side-by-side preview + settings on regular width (macOS/iPad); a vertical stack on
    /// compact width (iPhone) where a 320pt settings column would leave no room for the preview.
    @ViewBuilder
    private var mainLayout: some View {
        #if os(iOS)
        if horizontalSizeClass == .compact {
            VStack(spacing: 0) {
                previewColumn
                    .frame(maxWidth: .infinity, maxHeight: 320)
                    .background(Color.platformUnderPageBackground)

                Divider()

                settingsPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            regularSplitLayout
        }
        #else
        regularSplitLayout
        #endif
    }

    @ViewBuilder
    private var regularSplitLayout: some View {
        HStack(alignment: .top, spacing: 0) {
            previewColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.platformUnderPageBackground)

            Divider()

            settingsPanel
                .frame(width: ShowcaseExportSheetMetrics.settingsPanelWidth)
                .frame(maxHeight: .infinity)
        }
    }

    // MARK: - Preview column

    @ViewBuilder
    private var previewColumn: some View {
        ShowcasePreviewColumn(
            rows: selection.selectedRowsOrdered,
            config: config,
            transientBackgroundImages: transientBackgroundImages,
            loadImages: loadImages,
            localeCode: localeCode,
            localeState: localeState,
            availableFontFamilies: availableFontFamilies
        )
    }

    // MARK: - Settings panel

    @ViewBuilder
    private var settingsPanel: some View {
        ShowcaseSettingsPanel(
            candidateRows: candidateRows,
            selectedRowIds: $selectedRowIds,
            excludedTemplateIds: $excludedTemplateIds,
            config: $config,
            backgroundImage: backgroundImage,
            predictedOutputDimensionsText: predictedOutputDimensionsText,
            sampleRowForAspectPreview: selection.sampleRow,
            onReset: { showingResetConfirmation = true },
            onPickBackgroundImage: pickBackgroundImage,
            onRemoveBackgroundImage: removeBackgroundImage,
            onSetBackgroundImage: setBackgroundImage,
            onSetBackgroundSvg: setBackgroundSvg
        )
    }

    /// Predicted export dimensions for the first selected row, so the user sees
    /// the actual output size before clicking Export.
    private var predictedOutputDimensionsText: String {
        guard let row = selection.sampleRow else { return "" }
        let size = ShowcaseLayout(row: row, config: config)
            .outputSize(maxDimension: config.maxOutputDimension)
        return "\(Int(size.width)) × \(Int(size.height)) px"
    }

    private var exportCountText: LocalizedStringKey {
        switch selection.summary {
        case .empty: "No rows selected"
        case .all(let count): "Exporting all \(count) rows"
        case .partial(let count, let total): "Exporting \(count) of \(total) rows"
        }
    }

    // MARK: - Export destination menu (iPad)

    #if os(iOS)
    @ViewBuilder
    private var exportDestinationMenu: some View {
        let count = selection.selectedRowsOrdered.count
        Section(exportDestinationTitle(count)) {
            Button { export(to: .photos) } label: {
                Label("Save to Photos", systemImage: "photo.on.rectangle")
            }
            Button { export(to: .files) } label: {
                Label("Save to Files", systemImage: "folder")
            }
            Button { export(to: .share) } label: {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
        }
    }

    private func exportDestinationTitle(_ screenshotCount: Int) -> LocalizedStringKey {
        screenshotCount == 1 ? "Export 1 screenshot to…" : "Export \(screenshotCount) screenshots to…"
    }
    #endif

    private func export(to destination: ExportDestination) {
        onExport(config, backgroundImage, selectedRowIds, excludedTemplateIds, destination)
    }

    // MARK: - Footer

    #if os(macOS)
    @ViewBuilder
    private var footer: some View {
        HStack {
            HelpTopicButton(section: .showcase)
                .buttonStyle(.borderless)
                .focusable(false)
            if candidateRows.count > 1 {
                Text(exportCountText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Export…") { export(to: .files) }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(selection.selectedRowsOrdered.isEmpty)
        }
        .padding(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
    }
    #endif

    // MARK: - Background image handling

    private func pickBackgroundImage() {
        Task { @MainActor in
            switch await SvgHelper.pickImageOrSvg() {
            case .svg(let svg): setBackgroundSvg(svg)
            case .image(let image): setBackgroundImage(image)
            case .none: break
            }
        }
    }

    private func setBackgroundImage(_ image: NSImage) {
        backgroundImage = image
        config.backgroundImageConfig.fileName = ShowcaseExportConfig.transientBackgroundKey
        config.backgroundImageConfig.svgContent = nil
        config.backgroundStyle = .image
    }

    private func setBackgroundSvg(_ svg: String) {
        backgroundImage = nil
        config.backgroundImageConfig.fileName = nil
        config.backgroundImageConfig.svgContent = svg
        config.backgroundStyle = .image
    }

    private func removeBackgroundImage() {
        backgroundImage = nil
        config.backgroundImageConfig.fileName = nil
        config.backgroundImageConfig.svgContent = nil
    }

    private func resetShowcaseSettings() {
        withAnimation(.easeInOut(duration: 0.15)) {
            config = ShowcaseExportConfig()
            backgroundImage = nil
            excludedTemplateIds = []
        }
    }
}
