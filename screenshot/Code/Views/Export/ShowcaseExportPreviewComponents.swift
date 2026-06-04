import SwiftUI

// MARK: - Aspect preset thumbnail

/// Renders a tiny preview of how the user's row will lay out at the given aspect
/// ratio, so each preset tile shows actual content shape rather than a generic box.
struct ShowcasePresetThumbnail: View {
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

    var canvasFill: Color {
        selected ? Color.white.opacity(0.18) : Color.primary.opacity(0.06)
    }

    var borderColor: Color {
        selected ? Color.white.opacity(0.7) : Color.primary.opacity(0.35)
    }

    var tileColor: Color {
        selected ? Color.white.opacity(0.85) : Color.primary.opacity(0.45)
    }

    @ViewBuilder
    func miniLayout(in size: CGSize, row: ScreenshotRow) -> some View {
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

struct BackgroundSummarySwatch: View {
    let config: ShowcaseExportConfig
    let backgroundImage: NSImage?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.chip, style: .continuous)
        shape
            .fill(Color.platformControlBackground)
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
    var emptyImagePlaceholder: some View {
        if config.backgroundStyle == .image,
           backgroundImage == nil,
           config.backgroundImageConfig.svgContent == nil {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

struct NumericPercentField: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    @State var text: String
    @FocusState var isFocused: Bool

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

    static func format(_ v: Double) -> String {
        String(format: "%.1f%%", v)
    }

    func commit() {
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

struct ShowcaseRowPreview: View {
    let row: ScreenshotRow
    let config: ShowcaseExportConfig
    let transientBackgroundImages: [String: NSImage]
    let containerSize: CGSize
    let loadImages: () -> [String: NSImage]
    let localeCode: String?
    let localeState: LocaleState
    let availableFontFamilies: Set<String>?

    @State var templateImages: [NSImage] = []

    var body: some View {
        let layout = ShowcaseLayout(row: row, config: config)
        let scale = fitScale(layout: layout)
        // Render previews at ~2x the displayed size — crisp on screen but cheap, never full
        // model scale (a wide row at 1x exceeds the iPad GPU texture limit and renders blank).
        let renderScale = min(1.0, scale * 2)
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
        // Re-render when the template set changes (exclusion edits keep the same row.id) OR when
        // the render scale settles — the container width isn't final on first appearance, so a
        // task that captured an early small scale would otherwise leave the row permanently
        // low-res. Bucket the scale so sub-pixel jitter doesn't thrash re-renders.
        .task(id: RenderKey(ids: row.templates.map(\.id), scaleBucket: Int((renderScale * 20).rounded()))) {
            await renderTemplates(renderScale: renderScale)
        }
    }

    struct RenderKey: Equatable {
        let ids: [UUID]
        let scaleBucket: Int
    }

    func fitScale(layout: ShowcaseLayout) -> CGFloat {
        let widthScale = containerSize.width / layout.totalWidth
        guard containerSize.height.isFinite else { return min(widthScale, 1.0) }
        let heightBudget = max(containerSize.height - ShowcaseExportSheetMetrics.previewCaptionHeight, 1)
        let heightScale = heightBudget / layout.totalHeight
        return min(widthScale, heightScale, 1.0)
    }

    func renderTemplates(renderScale: CGFloat) async {
        let rowImages = loadImages()
        let rowBackground = ExportService.precomposedRowBackgroundIfNeeded(
            row: row,
            screenshotImages: rowImages,
            displayScale: renderScale,
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
                displayScale: renderScale,
                preRenderedRowBackground: rowBackground
            ))
        }
        guard !Task.isCancelled else { return }
        templateImages = rendered
    }
}
