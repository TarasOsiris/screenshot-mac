import SwiftUI
import UniformTypeIdentifiers

private enum ShowcaseExportSheetMetrics {
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
    var onExport: (ShowcaseExportConfig, NSImage?, Set<UUID>, Set<UUID>) -> Void

    @Environment(\.dismiss) private var dismiss
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
        onExport: @escaping (ShowcaseExportConfig, NSImage?, Set<UUID>, Set<UUID>) -> Void
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
                    .background(Color(NSColor.underPageBackgroundColor))

                Divider()

                settingsPanel
                    .frame(width: ShowcaseExportSheetMetrics.settingsPanelWidth)
                    .frame(maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            footer
                .frame(height: ShowcaseExportSheetMetrics.footerHeight)
                .frame(maxWidth: .infinity)
        }
        .frame(
            minWidth: ShowcaseExportSheetMetrics.minWidth,
            idealWidth: ShowcaseExportSheetMetrics.idealWidth,
            maxWidth: ShowcaseExportSheetMetrics.maxWidth,
            minHeight: ShowcaseExportSheetMetrics.minHeight,
            idealHeight: ShowcaseExportSheetMetrics.idealHeight,
            maxHeight: ShowcaseExportSheetMetrics.maxHeight
        )
        .alert("Reset Showcase Settings?", isPresented: $showingResetConfirmation) {
            Button("Reset", role: .destructive) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    config = ShowcaseExportConfig()
                    backgroundImage = nil
                    excludedTemplateIds = []
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Format, background, layout, and excluded screenshots will return to defaults. Row selection is preserved.")
        }
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
                    multiRowPreview(contentWidth: contentWidth, inset: inset)
                }
            }
        }
    }

    @ViewBuilder
    private func multiRowPreview(contentWidth: CGFloat, inset: CGFloat) -> some View {
        let useTwoColumns = contentWidth >= ShowcaseExportSheetMetrics.gridTwoColumnThreshold
            && selectedRowsOrdered.count >= 2
        let columnCount = useTwoColumns ? 2 : 1
        let spacing = ShowcaseExportSheetMetrics.previewItemSpacing
        let columnWidth = useTwoColumns
            ? max((contentWidth - spacing) / 2, 80)
            : contentWidth

        ScrollView(.vertical) {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(minimum: 80), spacing: spacing, alignment: .top),
                    count: columnCount
                ),
                spacing: spacing
            ) {
                ForEach(selectedRowsOrdered) { row in
                    ShowcaseRowPreview(
                        row: row,
                        config: config,
                        transientBackgroundImages: transientBackgroundImages,
                        containerSize: CGSize(width: columnWidth, height: .infinity),
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
                sectionTitle("Output Size", systemImage: "ruler")
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
                    .fill(selected ? Color.accentColor : Color(NSColor.controlBackgroundColor))
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

    private var exportCountText: LocalizedStringKey {
        let count = selectedRowIds.count
        if count == 0 { return "No rows selected" }
        if count == candidateRows.count { return "Exporting all \(count) rows" }
        return "Exporting \(count) of \(candidateRows.count) rows"
    }

    @ViewBuilder
    private func rowToggle(_ row: ScreenshotRow) -> some View {
        let rowSelected = selectedRowIds.contains(row.id)
        let binding = Binding<Bool>(
            get: { rowSelected },
            set: { isOn in
                if isOn { selectedRowIds.insert(row.id) } else { selectedRowIds.remove(row.id) }
            }
        )
        let includedCount = row.templates.count(where: { !excludedTemplateIds.contains($0.id) })

        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: binding) {
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
            .toggleStyle(.checkbox)

            if rowSelected, row.templates.count > 1 {
                templateChipStrip(row)
                    .padding(.leading, 18)
            }
        }
        .padding(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 6))
    }

    @ViewBuilder
    private func templateChipStrip(_ row: ScreenshotRow) -> some View {
        HStack(spacing: 4) {
            ForEach(row.templates.indices, id: \.self) { index in
                templateChip(index: index, template: row.templates[index])
            }
        }
    }

    @ViewBuilder
    private func templateChip(index: Int, template: ScreenshotTemplate) -> some View {
        let included = !excludedTemplateIds.contains(template.id)
        let shape = RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.chip, style: .continuous)
        Button {
            if included {
                excludedTemplateIds.insert(template.id)
            } else {
                excludedTemplateIds.remove(template.id)
            }
        } label: {
            Text("\(index + 1)")
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .frame(width: 20, height: 18)
                .background(
                    shape.fill(included
                               ? Color.accentColor.opacity(UIMetrics.Opacity.accentBadge)
                               : Color.primary.opacity(UIMetrics.Opacity.sectionFill))
                )
                .overlay(
                    shape.strokeBorder(
                        included
                            ? Color.accentColor.opacity(UIMetrics.Opacity.accentBorder)
                            : Color.primary.opacity(UIMetrics.Opacity.sectionBorder),
                        lineWidth: UIMetrics.BorderWidth.hairline
                    )
                )
                .foregroundStyle(included ? Color.accentColor : Color.secondary)
                .opacity(included ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .help(included ? "Exclude screenshot \(index + 1)" : "Include screenshot \(index + 1)")
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
        .help(preset.hint)
    }

    // MARK: - Background section

    @ViewBuilder
    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                sectionTitle("Background", systemImage: "paintpalette")
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
                onExport(config, backgroundImage, selectedRowIds, excludedTemplateIds)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(selectedRowsOrdered.isEmpty)
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

// MARK: - Aspect preset thumbnail

/// Renders a tiny preview of how the user's row will lay out at the given aspect
/// ratio, so each preset tile shows actual content shape rather than a generic box.
private struct ShowcasePresetThumbnail: View {
    let aspectRatio: CGFloat
    let sampleRow: ScreenshotRow?
    let config: ShowcaseExportConfig
    let selected: Bool

    var body: some View {
        GeometryReader { geo in
            let maxW = geo.size.width
            let maxH = geo.size.height
            let (w, h): (CGFloat, CGFloat) = aspectRatio >= 1
                ? (min(maxW, maxH * aspectRatio), min(maxW, maxH * aspectRatio) / aspectRatio)
                : (min(maxH, maxW / aspectRatio) * aspectRatio, min(maxH, maxW / aspectRatio))

            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(canvasFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(borderColor, lineWidth: 1)
                    )
                    .frame(width: w, height: h)

                if let sampleRow {
                    miniLayout(in: CGSize(width: w, height: h), row: sampleRow)
                }
            }
            .frame(width: maxW, height: maxH)
        }
    }

    private var canvasFill: Color {
        selected ? Color.white.opacity(0.18) : Color.primary.opacity(0.06)
    }

    private var borderColor: Color {
        selected ? Color.white.opacity(0.7) : Color.primary.opacity(0.35)
    }

    private var tileColor: Color {
        selected ? Color.white.opacity(0.85) : Color.primary.opacity(0.45)
    }

    @ViewBuilder
    private func miniLayout(in size: CGSize, row: ScreenshotRow) -> some View {
        // Mirror ShowcaseLayout's 2-row threshold so the thumbnail matches export.
        let count = max(row.templates.count, 1)
        let rowCount = (count >= 8 && count % 2 == 0) ? 2 : 1
        let columns = rowCount == 2 ? count / 2 : count
        let templateAspect: CGFloat = row.templateHeight > 0
            ? row.templateWidth / row.templateHeight : 0.5

        let paddingFraction = CGFloat(config.paddingPercent / 100) * 0.6
        let outerPaddingX = max(2, size.width * paddingFraction)
        let outerPaddingY = max(2, size.height * paddingFraction)
        let availableW = max(size.width - outerPaddingX * 2, 0)
        let availableH = max(size.height - outerPaddingY * 2, 0)
        let gapFraction = CGFloat(config.spacingPercent / 100)
        let gapW = availableW * gapFraction
        let gapH = availableH * gapFraction

        let tileW = max((availableW - gapW * CGFloat(columns - 1)) / CGFloat(columns), 1)
        let unconstrainedH = templateAspect > 0 ? tileW / templateAspect : tileW * 1.6
        let totalContentH = CGFloat(rowCount) * unconstrainedH + CGFloat(rowCount - 1) * gapH
        let scale: CGFloat = totalContentH > availableH && totalContentH > 0
            ? availableH / totalContentH : 1
        let finalTileW = tileW * scale
        let finalTileH = unconstrainedH * scale
        let finalGapW = gapW * scale
        let finalGapH = gapH * scale
        let cornerRadius = max(0.5, finalTileH * CGFloat(config.cornerRadiusPercent / 100))

        VStack(spacing: finalGapH) {
            ForEach(0..<rowCount, id: \.self) { _ in
                HStack(spacing: finalGapW) {
                    ForEach(0..<columns, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tileColor)
                            .frame(width: finalTileW, height: finalTileH)
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - Background summary swatch

private struct BackgroundSummarySwatch: View {
    let config: ShowcaseExportConfig
    let backgroundImage: NSImage?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.chip, style: .continuous)
        shape
            .fill(Color(NSColor.controlBackgroundColor))
            .overlay(
                config.backgroundFillView(image: backgroundImage)
                    .overlay(emptyImagePlaceholder)
            )
            .overlay(
                shape.strokeBorder(UIMetrics.Stroke.subtle, lineWidth: UIMetrics.BorderWidth.hairline)
            )
            .clipShape(shape)
    }

    @ViewBuilder
    private var emptyImagePlaceholder: some View {
        if config.backgroundStyle == .image,
           backgroundImage == nil,
           config.backgroundImageConfig.svgContent == nil {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

private struct NumericPercentField: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    @State private var text: String
    @FocusState private var isFocused: Bool

    init(value: Binding<Double>, range: ClosedRange<Double>, step: Double = 0.5) {
        self._value = value
        self.range = range
        self.step = step
        self._text = State(initialValue: Self.format(value.wrappedValue))
    }

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11))
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .focused($isFocused)
            .onChange(of: value) {
                if !isFocused { text = Self.format(value) }
            }
            .onChange(of: isFocused) {
                if !isFocused { commit() }
            }
            .onSubmit { commit() }
    }

    private static func format(_ v: Double) -> String {
        String(format: "%.1f%%", v)
    }

    private func commit() {
        let cleaned = text.replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespaces)
        if let parsed = Double(cleaned) {
            let clamped = min(max(parsed, range.lowerBound), range.upperBound)
            let snapped = step > 0 ? (clamped / step).rounded() * step : clamped
            value = snapped
        }
        text = Self.format(value)
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
        let outputSize = layout.outputSize(maxDimension: config.maxOutputDimension)

        VStack(spacing: 6) {
            HStack {
                Text(row.displayLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Text("\(Int(outputSize.width)) × \(Int(outputSize.height)) px")
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
        // Re-render when templates change (e.g., user excludes one) — keying on row.id
        // alone would miss exclusion edits since the parent passes the same row id.
        .task(id: row.templates.map(\.id)) { await renderTemplates() }
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
