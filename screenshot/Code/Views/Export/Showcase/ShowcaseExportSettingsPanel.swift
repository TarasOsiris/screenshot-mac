import SwiftUI

struct ShowcaseSettingsPanel: View {
    let candidateRows: [ScreenshotRow]
    @Binding var selectedRowIds: Set<UUID>
    @Binding var excludedTemplateIds: Set<UUID>
    @Binding var config: ShowcaseExportConfig
    let backgroundImage: NSImage?
    let predictedOutputDimensionsText: String
    let sampleRowForAspectPreview: ScreenshotRow?
    let onReset: () -> Void
    let onPickBackgroundImage: () -> Void
    let onRemoveBackgroundImage: () -> Void
    let onSetBackgroundImage: (NSImage) -> Void
    let onSetBackgroundSvg: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ShowcaseSettingsPanelHeader(onReset: onReset)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if candidateRows.count > 1 {
                        ShowcaseRowsSection(
                            candidateRows: candidateRows,
                            selectedRowIds: $selectedRowIds,
                            excludedTemplateIds: $excludedTemplateIds
                        )
                    }
                    ShowcaseFormatSection(
                        config: $config,
                        sampleRowForAspectPreview: sampleRowForAspectPreview
                    )
                    ShowcaseOutputSizeSection(
                        config: $config,
                        predictedOutputDimensionsText: predictedOutputDimensionsText
                    )
                    ShowcaseBackgroundSection(
                        config: $config,
                        backgroundImage: backgroundImage,
                        onPickImage: onPickBackgroundImage,
                        onRemoveImage: onRemoveBackgroundImage,
                        onDropImage: onSetBackgroundImage,
                        onDropSvg: onSetBackgroundSvg
                    )
                    ShowcaseLayoutSection(config: $config)
                }
                .padding(EdgeInsets(top: 16, leading: 24, bottom: 16, trailing: 16))
            }
        }
    }
}

private struct ShowcaseSettingsPanelHeader: View {
    let onReset: () -> Void

    var body: some View {
        HStack {
            Text("Showcase")
                .font(.headline)
            Spacer()
            Button(action: onReset) {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.borderless)
            .help("Reset to defaults")
        }
        .padding(EdgeInsets(top: 14, leading: 24, bottom: 14, trailing: 16))
    }
}

private struct ShowcaseOutputSizeSection: View {
    @Binding var config: ShowcaseExportConfig
    let predictedOutputDimensionsText: String

    private let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
    ]

    private var selectedSize: ShowcaseOutputSize? {
        ShowcaseOutputSize.matching(maxDimension: config.maxOutputDimension)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ShowcaseSectionTitle(text: "Output Size", systemImage: "ruler")
                Spacer()
                Text(predictedOutputDimensionsText)
                    .font(.system(size: UIMetrics.FontSize.numericBadge))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(ShowcaseOutputSize.allCases) { size in
                    ShowcaseOutputSizeTile(
                        size: size,
                        isSelected: selectedSize == size,
                        onSelect: { config.maxOutputDimension = size.maxDimension }
                    )
                }
            }
        }
    }
}

private struct ShowcaseOutputSizeTile: View {
    let size: ShowcaseOutputSize
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 1) {
                Text(size.label)
                    .font(.system(size: UIMetrics.FontSize.body, weight: .medium))
                Text(size.caption)
                    .font(.system(size: UIMetrics.FontSize.hint))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.75) : .secondary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(tileBackground)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .overlay { tileBorder }
        }
        .buttonStyle(.plain)
    }

    private var tileBackground: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(isSelected ? Color.accentColor : Color.platformControlBackground)
    }

    private var tileBorder: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(
                isSelected ? Color.clear : Color.primary.opacity(0.08),
                lineWidth: 1
            )
    }
}

private struct ShowcaseFormatSection: View {
    @Binding var config: ShowcaseExportConfig
    let sampleRowForAspectPreview: ScreenshotRow?

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    private var selectedPreset: ShowcaseAspectPreset? {
        ShowcaseAspectPreset.matching(ratio: config.aspectRatio)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ShowcaseSectionTitle(text: "Format", systemImage: "aspectratio")

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(ShowcaseAspectPreset.allCases) { preset in
                    ShowcaseAspectPresetTile(
                        preset: preset,
                        isSelected: selectedPreset == preset,
                        sampleRow: sampleRowForAspectPreview,
                        config: config,
                        onSelect: { config.aspectRatio = preset.ratio }
                    )
                }
            }
        }
    }
}

private struct ShowcaseAspectPresetTile: View {
    let preset: ShowcaseAspectPreset
    let isSelected: Bool
    let sampleRow: ScreenshotRow?
    let config: ShowcaseExportConfig
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 6) {
                ShowcasePresetThumbnail(
                    aspectRatio: CGFloat(preset.ratio),
                    sampleRow: sampleRow,
                    config: config,
                    selected: isSelected
                )
                .frame(height: 36)

                titleStack
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(tileBackground)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .overlay { tileBorder }
        }
        .buttonStyle(.plain)
        .help(preset.hint)
    }

    private var titleStack: some View {
        VStack(spacing: 1) {
            Text(preset.label)
                .font(.system(size: UIMetrics.FontSize.body, weight: .medium))
            Text(preset.shortRatio)
                .font(.system(size: UIMetrics.FontSize.inlineLabel))
                .foregroundStyle(isSelected ? Color.white.opacity(0.75) : .secondary)
                .monospacedDigit()
        }
    }

    private var tileBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isSelected ? Color.accentColor : Color.platformControlBackground)
    }

    private var tileBorder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(
                isSelected ? Color.clear : Color.primary.opacity(0.08),
                lineWidth: 1
            )
    }
}

private struct ShowcaseBackgroundSection: View {
    @Binding var config: ShowcaseExportConfig
    let backgroundImage: NSImage?
    let onPickImage: () -> Void
    let onRemoveImage: () -> Void
    let onDropImage: (NSImage) -> Void
    let onDropSvg: (String) -> Void

    private var summaryText: String {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ShowcaseSectionTitle(text: "Background", systemImage: "paintpalette")
                Spacer()
                BackgroundSummarySwatch(
                    config: config,
                    backgroundImage: backgroundImage
                )
                .frame(width: 32, height: 18)
                Text(summaryText)
                    .font(.system(size: UIMetrics.FontSize.inlineLabel))
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
                onPickImage: onPickImage,
                onRemoveImage: onRemoveImage,
                onDropImage: onDropImage,
                onDropSvg: onDropSvg
            )
        }
    }
}

private struct ShowcaseLayoutSection: View {
    @Binding var config: ShowcaseExportConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ShowcaseSectionTitle(text: "Layout", systemImage: "rectangle.3.group")

            ShowcasePercentSliderRow("Corner Radius", value: $config.cornerRadiusPercent, range: 0...10)
            ShowcasePercentSliderRow("Gap", value: $config.spacingPercent, range: 0...12)
            ShowcasePercentSliderRow("Padding", value: $config.paddingPercent, range: 2...24)
        }
    }
}

private struct ShowcasePercentSliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    init(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) {
        self.label = label
        _value = value
        self.range = range
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.system(size: UIMetrics.FontSize.menuRow))
                Spacer()
                NumericPercentField(value: $value, range: range)
                    .frame(width: 56)
            }
            Slider(value: $value, in: range, step: 0.5)
                .compactControlSize()
        }
    }
}
