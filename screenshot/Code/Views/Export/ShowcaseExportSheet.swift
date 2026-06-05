import SwiftUI
import UniformTypeIdentifiers

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
    let availableFontFamilies: Set<String>?
    var onExport: (ShowcaseExportConfig, NSImage?, Set<UUID>, Set<UUID>, ExportDestination) -> Void

    #if os(macOS)
    @Environment(\.dismiss) private var dismiss
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
        availableFontFamilies: Set<String>?,
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

    /// Selected rows in their candidate order, with excluded templates filtered out.
    /// Rows whose templates are all excluded are dropped — they would render empty.
    private var selectedRowsOrdered: [ScreenshotRow] {
        candidateRows
            .filter { selectedRowIds.contains($0.id) }
            .compactMap { $0.filtering(excluding: excludedTemplateIds) }
    }

    /// Row used to render aspect preset thumbnails. Prefers a selected row so the
    /// thumbnails reflect what the user is about to export; falls back to the first
    /// candidate, then to nil if there are none.
    private var sampleRowForAspectPreview: ScreenshotRow? {
        selectedRowsOrdered.first ?? candidateRows.first
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                previewColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.platformUnderPageBackground)

                Divider()

                settingsPanel
                    .frame(width: ShowcaseExportSheetMetrics.settingsPanelWidth)
                    .frame(maxHeight: .infinity)
            }
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
            confirmDisabled: selectedRowsOrdered.isEmpty,
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

    // MARK: - Preview column

    @ViewBuilder
    private var previewColumn: some View {
        ShowcasePreviewColumn(
            rows: selectedRowsOrdered,
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
        VStack(alignment: .leading, spacing: 0) {
            panelHeader

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if candidateRows.count > 1 {
                        rowsSection
                    }
                    formatSection
                    sizeSection
                    backgroundSection
                    layoutSection
                }
                .padding(EdgeInsets(top: 16, leading: 24, bottom: 16, trailing: 16))
            }
        }
    }

    // MARK: - Size section

    @ViewBuilder
    private var sizeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ShowcaseSectionTitle(text: "Output Size", systemImage: "ruler")
                Spacer()
                Text(predictedOutputDimensionsText)
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            let selected = ShowcaseOutputSize.matching(maxDimension: config.maxOutputDimension)
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6),
                          GridItem(.flexible(), spacing: 6)],
                spacing: 6
            ) {
                ForEach(ShowcaseOutputSize.allCases) { size in
                    sizeTile(size, selected: selected == size)
                }
            }
        }
    }

    @ViewBuilder
    private func sizeTile(_ size: ShowcaseOutputSize, selected: Bool) -> some View {
        Button {
            config.maxOutputDimension = size.maxDimension
        } label: {
            VStack(spacing: 1) {
                Text(size.label)
                    .font(.system(size: 11, weight: .medium))
                Text(size.caption)
                    .font(.system(size: 9))
                    .foregroundStyle(selected ? Color.white.opacity(0.75) : .secondary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? Color.accentColor : Color.platformControlBackground)
            )
            .foregroundStyle(selected ? Color.white : Color.primary)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        selected ? Color.clear : Color.primary.opacity(0.08),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    /// Predicted export dimensions for the first selected row, so the user sees
    /// the actual output size before clicking Export.
    private var predictedOutputDimensionsText: String {
        let rows = selectedRowsOrdered.isEmpty ? candidateRows : selectedRowsOrdered
        guard let row = rows.first else { return "" }
        let size = ShowcaseLayout(row: row, config: config)
            .outputSize(maxDimension: config.maxOutputDimension)
        return "\(Int(size.width)) × \(Int(size.height)) px"
    }

    // MARK: - Rows section

    @ViewBuilder
    private var rowsSection: some View {
        ShowcaseRowsSection(
            candidateRows: candidateRows,
            selectedRowIds: $selectedRowIds,
            excludedTemplateIds: $excludedTemplateIds
        )
    }

    private var exportCountText: LocalizedStringKey {
        let count = selectedRowIds.count
        if count == 0 { return "No rows selected" }
        if count == candidateRows.count { return "Exporting all \(count) rows" }
        return "Exporting \(count) of \(candidateRows.count) rows"
    }

    @ViewBuilder
    private var panelHeader: some View {
        HStack {
            Text("Showcase")
                .font(.headline)
            Spacer()
            Button {
                showingResetConfirmation = true
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.borderless)
            .help("Reset to defaults")
        }
        .padding(EdgeInsets(top: 14, leading: 24, bottom: 14, trailing: 16))
    }

    // MARK: - Format section

    @ViewBuilder
    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ShowcaseSectionTitle(text: "Format", systemImage: "aspectratio")

            let selectedPreset = ShowcaseAspectPreset.matching(ratio: config.aspectRatio)
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                spacing: 8
            ) {
                ForEach(ShowcaseAspectPreset.allCases) { preset in
                    presetTile(preset, selected: selectedPreset == preset)
                }
            }
        }
    }

    @ViewBuilder
    private func presetTile(_ preset: ShowcaseAspectPreset, selected: Bool) -> some View {
        Button {
            config.aspectRatio = preset.ratio
        } label: {
            VStack(spacing: 6) {
                ShowcasePresetThumbnail(
                    aspectRatio: CGFloat(preset.ratio),
                    sampleRow: sampleRowForAspectPreview,
                    config: config,
                    selected: selected
                )
                .frame(height: 36)

                VStack(spacing: 1) {
                    Text(preset.label)
                        .font(.system(size: 11, weight: .medium))
                    Text(preset.shortRatio)
                        .font(.system(size: 10))
                        .foregroundStyle(selected ? Color.white.opacity(0.75) : .secondary)
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.accentColor : Color.platformControlBackground)
            )
            .foregroundStyle(selected ? Color.white : Color.primary)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        selected ? Color.clear : Color.primary.opacity(0.08),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .help(preset.hint)
    }

    // MARK: - Background section

    @ViewBuilder
    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ShowcaseSectionTitle(text: "Background", systemImage: "paintpalette")
                Spacer()
                BackgroundSummarySwatch(
                    config: config,
                    backgroundImage: backgroundImage
                )
                .frame(width: 32, height: 18)
                Text(backgroundSummaryText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            BackgroundEditor(
                backgroundStyle: $config.backgroundStyle,
                bgColor: $config.bgColor,
                gradientConfig: $config.gradientConfig,
                backgroundImageConfig: $config.backgroundImageConfig,
                backgroundImage: backgroundImage,
                onChanged: {},
                onPickImage: pickBackgroundImage,
                onRemoveImage: removeBackgroundImage,
                onDropImage: { image in setBackgroundImage(image) },
                onDropSvg: { svg in setBackgroundSvg(svg) }
            )
        }
    }

    private var backgroundSummaryText: String {
        switch config.backgroundStyle {
        case .color: return String(localized: "Solid")
        case .gradient:
            switch config.gradientConfig.gradientType {
            case .linear: return String(localized: "Linear")
            case .radial: return String(localized: "Radial")
            case .angular: return String(localized: "Angular")
            }
        case .image:
            if backgroundImage != nil { return String(localized: "Image") }
            if config.backgroundImageConfig.svgContent != nil { return String(localized: "SVG") }
            return String(localized: "None")
        }
    }

    // MARK: - Layout section

    @ViewBuilder
    private var layoutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ShowcaseSectionTitle(text: "Layout", systemImage: "rectangle.3.group")

            sliderRow("Corner Radius", value: $config.cornerRadiusPercent, range: 0...10)
            sliderRow("Gap", value: $config.spacingPercent, range: 0...12)
            sliderRow("Padding", value: $config.paddingPercent, range: 2...24)
        }
    }

    // MARK: - Shared pieces

    @ViewBuilder
    private func sliderRow(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.system(size: 12))
                Spacer()
                NumericPercentField(value: value, range: range)
                    .frame(width: 56)
            }
            Slider(value: value, in: range, step: 0.5)
                .controlSize(.small)
        }
    }

    // MARK: - Export destination menu (iPad)

    #if os(iOS)
    @ViewBuilder
    private var exportDestinationMenu: some View {
        let count = selectedRowsOrdered.count
        Section(count == 1 ? "Export 1 screenshot to…" : "Export \(count) screenshots to…") {
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

    private func export(to destination: ExportDestination) {
        onExport(config, backgroundImage, selectedRowIds, excludedTemplateIds, destination)
    }
    #endif

    // MARK: - Footer

    #if os(macOS)
    @ViewBuilder
    private var footer: some View {
        HStack {
            if candidateRows.count > 1 {
                Text(exportCountText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Export…") {
                onExport(config, backgroundImage, selectedRowIds, excludedTemplateIds, .files)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(selectedRowsOrdered.isEmpty)
        }
        .padding(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
    }
    #endif

    // MARK: - Background image handling

    private func pickBackgroundImage() {
        switch SvgHelper.pickImageOrSvg() {
        case .svg(let svg): setBackgroundSvg(svg)
        case .image(let image): setBackgroundImage(image)
        case .none: break
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

private struct ShowcasePreviewColumn: View {
    let rows: [ScreenshotRow]
    let config: ShowcaseExportConfig
    let transientBackgroundImages: [String: NSImage]
    let loadImages: (ScreenshotRow) -> [String: NSImage]
    let localeCode: String?
    let localeState: LocaleState
    let availableFontFamilies: Set<String>?

    var body: some View {
        if rows.isEmpty {
            emptyPreview
        } else {
            GeometryReader { geo in
                let inset = ShowcaseExportSheetMetrics.previewContentInset
                let contentWidth = max(geo.size.width - inset * 2, 80)
                if rows.count == 1 {
                    singleRowPreview(row: rows[0], geo: geo, inset: inset, contentWidth: contentWidth)
                } else {
                    multiRowPreview(contentWidth: contentWidth, inset: inset)
                }
            }
        }
    }

    private func singleRowPreview(
        row: ScreenshotRow,
        geo: GeometryProxy,
        inset: CGFloat,
        contentWidth: CGFloat
    ) -> some View {
        let contentHeight = max(geo.size.height - inset * 2, 80)
        return ShowcaseRowPreview(
            row: row,
            config: config,
            transientBackgroundImages: transientBackgroundImages,
            containerSize: CGSize(width: contentWidth, height: contentHeight),
            loadImages: { loadImages(row) },
            localeCode: localeCode,
            localeState: localeState,
            availableFontFamilies: availableFontFamilies
        )
        .padding(inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func multiRowPreview(contentWidth: CGFloat, inset: CGFloat) -> some View {
        let layout = ShowcasePreviewGridLayout(contentWidth: contentWidth, rowCount: rows.count)
        return ScrollView(.vertical) {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(minimum: 80), spacing: layout.spacing, alignment: .top),
                    count: layout.columnCount
                ),
                spacing: layout.spacing
            ) {
                ForEach(rows) { row in
                    ShowcaseRowPreview(
                        row: row,
                        config: config,
                        transientBackgroundImages: transientBackgroundImages,
                        containerSize: CGSize(width: layout.columnWidth, height: .infinity),
                        loadImages: { loadImages(row) },
                        localeCode: localeCode,
                        localeState: localeState,
                        availableFontFamilies: availableFontFamilies
                    )
                    .id(row.id)
                }
            }
            .padding(inset)
            .frame(maxWidth: .infinity)
        }
    }

    private var emptyPreview: some View {
        ContentUnavailableView(
            "No rows selected",
            systemImage: "rectangle.stack.badge.minus",
            description: Text("Select at least one row to preview and export.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ShowcasePreviewGridLayout {
    let contentWidth: CGFloat
    let rowCount: Int

    var spacing: CGFloat {
        ShowcaseExportSheetMetrics.previewItemSpacing
    }

    var columnCount: Int {
        contentWidth >= ShowcaseExportSheetMetrics.gridTwoColumnThreshold && rowCount >= 2 ? 2 : 1
    }

    var columnWidth: CGFloat {
        columnCount == 2 ? max((contentWidth - spacing) / 2, 80) : contentWidth
    }
}

private struct ShowcaseRowsSection: View {
    let candidateRows: [ScreenshotRow]
    @Binding var selectedRowIds: Set<UUID>
    @Binding var excludedTemplateIds: Set<UUID>

    private var allSelected: Bool {
        selectedRowIds.count == candidateRows.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            VStack(spacing: 2) {
                ForEach(candidateRows) { row in
                    ShowcaseRowToggle(
                        row: row,
                        selectedRowIds: $selectedRowIds,
                        excludedTemplateIds: $excludedTemplateIds
                    )
                }
            }
        }
    }

    private var header: some View {
        HStack {
            ShowcaseSectionTitle(text: "Rows", systemImage: "rectangle.stack")
            Spacer()
            Button(allSelected ? "None" : "All", action: toggleAllRows)
                .buttonStyle(.borderless)
                .font(.system(size: 10, weight: .semibold))
        }
    }

    private func toggleAllRows() {
        selectedRowIds = allSelected ? [] : Set(candidateRows.map(\.id))
    }
}

private struct ShowcaseRowToggle: View {
    let row: ScreenshotRow
    @Binding var selectedRowIds: Set<UUID>
    @Binding var excludedTemplateIds: Set<UUID>

    private var rowSelected: Bool {
        selectedRowIds.contains(row.id)
    }

    private var includedCount: Int {
        row.templates.count(where: { !excludedTemplateIds.contains($0.id) })
    }

    private var selectionBinding: Binding<Bool> {
        Binding(
            get: { rowSelected },
            set: { isOn in
                if isOn { selectedRowIds.insert(row.id) } else { selectedRowIds.remove(row.id) }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: selectionBinding) {
                HStack(spacing: 8) {
                    Text(row.displayLabel)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                    Text("\(includedCount)/\(row.templates.count)")
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            #if os(macOS)
            .toggleStyle(.checkbox)
            #endif

            if rowSelected, row.templates.count > 1 {
                templateChipStrip
                    .padding(.leading, 18)
            }
        }
        .padding(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 6))
    }

    private var templateChipStrip: some View {
        HStack(spacing: 4) {
            ForEach(row.templates.indices, id: \.self) { index in
                ShowcaseTemplateChip(
                    index: index,
                    template: row.templates[index],
                    excludedTemplateIds: $excludedTemplateIds
                )
            }
        }
    }
}

private struct ShowcaseTemplateChip: View {
    let index: Int
    let template: ScreenshotTemplate
    @Binding var excludedTemplateIds: Set<UUID>

    private var included: Bool {
        !excludedTemplateIds.contains(template.id)
    }

    var body: some View {
        Button(action: toggleIncluded) {
            Text("\(index + 1)")
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .frame(width: 20, height: 18)
                .background(chipShape.fill(chipFill))
                .overlay(chipShape.strokeBorder(chipStroke, lineWidth: UIMetrics.BorderWidth.hairline))
                .foregroundStyle(included ? Color.accentColor : Color.secondary)
                .opacity(included ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .help(included ? "Exclude screenshot \(index + 1)" : "Include screenshot \(index + 1)")
    }

    private var chipShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.chip, style: .continuous)
    }

    private var chipFill: Color {
        included
            ? Color.accentColor.opacity(UIMetrics.Opacity.accentBadge)
            : Color.primary.opacity(UIMetrics.Opacity.sectionFill)
    }

    private var chipStroke: Color {
        included
            ? Color.accentColor.opacity(UIMetrics.Opacity.accentBorder)
            : Color.primary.opacity(UIMetrics.Opacity.sectionBorder)
    }

    private func toggleIncluded() {
        if included {
            excludedTemplateIds.insert(template.id)
        } else {
            excludedTemplateIds.remove(template.id)
        }
    }
}

private struct ShowcaseSectionTitle: View {
    let text: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(text.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
        }
        .foregroundStyle(.secondary)
    }
}
