import SwiftUI
import UniformTypeIdentifiers

private enum ShowcaseExportSheetMetrics {
    static let sheetWidth: CGFloat = 1120
    static let sheetHeight: CGFloat = 760
    static let settingsPanelWidth: CGFloat = 320
    static let footerHeight: CGFloat = 56
    static let previewContentInset: CGFloat = 24
    static let previewItemSpacing: CGFloat = 24
    /// Vertical budget reserved for a row's caption (label + dimensions) above its preview.
    static let previewCaptionHeight: CGFloat = 24
}

struct ShowcaseExportSheet: View {
    let candidateRows: [ScreenshotRow]
    let loadImages: (ScreenshotRow) -> [String: NSImage]
    let localeCode: String?
    let localeState: LocaleState
    let availableFontFamilies: Set<String>?
    var onExport: (ShowcaseExportConfig, NSImage?, Set<UUID>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var config = ShowcaseExportConfig()
    @State private var backgroundImage: NSImage?
    @State private var selectedRowIds: Set<UUID>

    init(
        candidateRows: [ScreenshotRow],
        loadImages: @escaping (ScreenshotRow) -> [String: NSImage],
        localeCode: String?,
        localeState: LocaleState,
        availableFontFamilies: Set<String>?,
        onExport: @escaping (ShowcaseExportConfig, NSImage?, Set<UUID>) -> Void
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

    private var selectedRowsOrdered: [ScreenshotRow] {
        candidateRows.filter { selectedRowIds.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                previewColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.underPageBackgroundColor))

                Divider()

                settingsPanel
                    .frame(
                        width: ShowcaseExportSheetMetrics.settingsPanelWidth,
                        height: ShowcaseExportSheetMetrics.sheetHeight - ShowcaseExportSheetMetrics.footerHeight
                    )
            }
            .frame(
                width: ShowcaseExportSheetMetrics.sheetWidth,
                height: ShowcaseExportSheetMetrics.sheetHeight - ShowcaseExportSheetMetrics.footerHeight
            )

            Divider()

            footer
                .frame(
                    width: ShowcaseExportSheetMetrics.sheetWidth,
                    height: ShowcaseExportSheetMetrics.footerHeight
                )
        }
        .frame(
            width: ShowcaseExportSheetMetrics.sheetWidth,
            height: ShowcaseExportSheetMetrics.sheetHeight
        )
    }

    // MARK: - Preview column

    @ViewBuilder
    private var previewColumn: some View {
        if selectedRowsOrdered.isEmpty {
            emptyPreview
        } else {
            GeometryReader { geo in
                let inset = ShowcaseExportSheetMetrics.previewContentInset
                let contentWidth = max(geo.size.width - inset * 2, 80)
                if selectedRowsOrdered.count == 1 {
                    let row = selectedRowsOrdered[0]
                    let contentHeight = max(geo.size.height - inset * 2, 80)
                    ShowcaseRowPreview(
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
                } else {
                    ScrollView(.vertical) {
                        VStack(spacing: ShowcaseExportSheetMetrics.previewItemSpacing) {
                            ForEach(selectedRowsOrdered) { row in
                                ShowcaseRowPreview(
                                    row: row,
                                    config: config,
                                    transientBackgroundImages: transientBackgroundImages,
                                    containerSize: CGSize(width: contentWidth, height: .infinity),
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
            }
        }
    }

    @ViewBuilder
    private var emptyPreview: some View {
        ContentUnavailableView(
            "No rows selected",
            systemImage: "rectangle.stack.badge.minus",
            description: Text("Select at least one row to preview and export.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    backgroundSection
                    layoutSection
                }
                .padding(EdgeInsets(top: 16, leading: 24, bottom: 16, trailing: 16))
            }
        }
    }

    // MARK: - Rows section

    @ViewBuilder
    private var rowsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle("Rows", systemImage: "rectangle.stack")
                Spacer()
                Button(allSelected ? "None" : "All") {
                    selectedRowIds = allSelected ? [] : Set(candidateRows.map(\.id))
                }
                .buttonStyle(.borderless)
                .font(.system(size: 10, weight: .semibold))
            }

            VStack(spacing: 2) {
                ForEach(candidateRows) { row in
                    rowToggle(row)
                }
            }
        }
    }

    private var allSelected: Bool {
        selectedRowIds.count == candidateRows.count
    }

    private var exportCountText: String {
        let count = selectedRowIds.count
        if count == 0 { return "No rows selected" }
        if count == candidateRows.count { return "Exporting all \(count) rows" }
        return "Exporting \(count) of \(candidateRows.count) rows"
    }

    @ViewBuilder
    private func rowToggle(_ row: ScreenshotRow) -> some View {
        let isSelected = selectedRowIds.contains(row.id)
        Button {
            if isSelected {
                selectedRowIds.remove(row.id)
            } else {
                selectedRowIds.insert(row.id)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .font(.system(size: 13))
                Text(row.displayLabel)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Text("\(row.templates.count)")
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .foregroundStyle(.primary)
            .padding(EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var panelHeader: some View {
        HStack {
            Text("Showcase")
                .font(.headline)
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    config = ShowcaseExportConfig()
                    backgroundImage = nil
                }
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
            sectionTitle("Format", systemImage: "aspectratio")

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
                aspectIcon(preset, selected: selected)
                    .frame(height: 28)
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
                    .fill(selected ? Color.accentColor : Color(NSColor.controlBackgroundColor))
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
    }

    private func aspectIcon(_ preset: ShowcaseAspectPreset, selected: Bool) -> some View {
        let ratio = CGFloat(preset.ratio)
        let maxW: CGFloat = 42
        let maxH: CGFloat = 22
        let (w, h): (CGFloat, CGFloat) = ratio >= 1
            ? (maxW, maxW / ratio)
            : (maxH * ratio, maxH)
        return RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(selected ? Color.white.opacity(0.25) : Color.primary.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(
                        selected ? Color.white.opacity(0.7) : Color.primary.opacity(0.35),
                        lineWidth: 1
                    )
            )
            .frame(width: w, height: h)
    }

    // MARK: - Background section

    @ViewBuilder
    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Background", systemImage: "paintpalette")

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

    // MARK: - Layout section

    @ViewBuilder
    private var layoutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Layout", systemImage: "rectangle.3.group")

            sliderRow("Corner Radius", value: $config.cornerRadiusPercent, range: 0...10)
            sliderRow("Gap", value: $config.spacingPercent, range: 0...12)
            sliderRow("Padding", value: $config.paddingPercent, range: 2...24)
        }
    }

    // MARK: - Shared pieces

    @ViewBuilder
    private func sectionTitle(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(text.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
        }
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func sliderRow(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 12))
                Spacer()
                Text(String(format: "%.1f%%", value.wrappedValue))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range, step: 0.5)
                .controlSize(.small)
        }
    }

    // MARK: - Footer

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
                onExport(config, backgroundImage, selectedRowIds)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(selectedRowIds.isEmpty)
        }
        .padding(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
    }

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
}

// MARK: - Per-row preview item

private struct ShowcaseRowPreview: View {
    let row: ScreenshotRow
    let config: ShowcaseExportConfig
    let transientBackgroundImages: [String: NSImage]
    let containerSize: CGSize
    let loadImages: () -> [String: NSImage]
    let localeCode: String?
    let localeState: LocaleState
    let availableFontFamilies: Set<String>?

    @State private var templateImages: [NSImage] = []

    var body: some View {
        let layout = ShowcaseLayout(row: row, config: config)
        let scale = fitScale(layout: layout)
        let previewWidth = layout.totalWidth * scale
        let previewHeight = layout.totalHeight * scale

        VStack(spacing: 6) {
            HStack {
                Text(row.displayLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Text("\(Int(layout.totalWidth)) × \(Int(layout.totalHeight)) px")
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .frame(width: previewWidth)

            Group {
                if templateImages.isEmpty {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                        .overlay(ProgressView().controlSize(.small))
                } else {
                    let modelSize = CGSize(width: layout.totalWidth, height: layout.totalHeight)
                    ShowcaseRowView(
                        templateImages: templateImages,
                        templateWidth: row.templateWidth,
                        templateHeight: row.templateHeight,
                        layout: layout,
                        background: config.resolvedBackgroundView(
                            screenshotImages: transientBackgroundImages,
                            modelSize: modelSize
                        )
                        .frame(width: previewWidth, height: previewHeight),
                        scale: scale
                    )
                    .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 2)
                }
            }
            .frame(width: previewWidth, height: previewHeight)
        }
        .task(id: row.id) { await renderTemplates() }
    }

    private func fitScale(layout: ShowcaseLayout) -> CGFloat {
        let widthScale = containerSize.width / layout.totalWidth
        guard containerSize.height.isFinite else { return min(widthScale, 1.0) }
        let heightBudget = max(containerSize.height - ShowcaseExportSheetMetrics.previewCaptionHeight, 1)
        let heightScale = heightBudget / layout.totalHeight
        return min(widthScale, heightScale, 1.0)
    }

    private func renderTemplates() async {
        let rowImages = loadImages()
        let rowBackground = ExportService.renderComposedBackgroundImage(
            row: row,
            screenshotImages: rowImages,
            displayScale: 1.0,
            labelPrefix: "showcase preview"
        )
        var rendered: [NSImage] = []
        for i in 0..<row.templates.count {
            guard !Task.isCancelled else { return }
            await Task.yield()
            rendered.append(ExportService.renderSingleTemplateImage(
                index: i,
                row: row,
                screenshotImages: rowImages,
                localeCode: localeCode,
                localeState: localeState,
                availableFontFamilies: availableFontFamilies,
                preRenderedRowBackground: rowBackground
            ))
        }
        guard !Task.isCancelled else { return }
        templateImages = rendered
    }
}
