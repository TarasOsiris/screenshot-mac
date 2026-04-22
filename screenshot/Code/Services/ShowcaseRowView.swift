import Foundation
import SwiftUI

struct ShowcaseExportConfig: BackgroundFillable {
    /// In-memory key used for a user-picked background image. Never persisted;
    /// resolved at render time via the screenshotImages dictionary.
    static let transientBackgroundKey = "__showcase_bg__"

    var backgroundStyle: BackgroundStyle = .color
    var bgColor: Color = Color(white: 0.88)
    var gradientConfig: GradientConfig = GradientConfig()
    var backgroundImageConfig: BackgroundImageConfig = BackgroundImageConfig()
    var spacingPercent: Double = 3.0
    var paddingPercent: Double = 8.0
    var cornerRadiusPercent: Double = 2.5
    var aspectRatio: Double = ShowcaseAspectPreset.social.ratio
}

enum ShowcaseAspectPreset: String, CaseIterable, Identifiable {
    case social
    case square
    case portrait
    case story
    case youtube
    case pinterest

    var id: String { rawValue }

    var ratio: Double {
        switch self {
        case .social: return 1.91
        case .square: return 1.0
        case .portrait: return 4.0 / 5.0
        case .story: return 9.0 / 16.0
        case .youtube: return 16.0 / 9.0
        case .pinterest: return 2.0 / 3.0
        }
    }

    var label: String {
        switch self {
        case .social: return "Social"
        case .square: return "Square"
        case .portrait: return "Portrait"
        case .story: return "Story"
        case .youtube: return "YouTube"
        case .pinterest: return "Pinterest"
        }
    }

    var shortRatio: String {
        switch self {
        case .social: return "1.91:1"
        case .square: return "1:1"
        case .portrait: return "4:5"
        case .story: return "9:16"
        case .youtube: return "16:9"
        case .pinterest: return "2:3"
        }
    }

    var hint: String {
        switch self {
        case .social: return "X, Facebook, LinkedIn"
        case .square: return "Instagram feed"
        case .portrait: return "Instagram portrait"
        case .story: return "Stories, Reels, TikTok"
        case .youtube: return "YouTube thumbnail"
        case .pinterest: return "Pinterest pin"
        }
    }

    static func matching(ratio: Double, tolerance: Double = 0.01) -> ShowcaseAspectPreset? {
        allCases.first { abs($0.ratio - ratio) < tolerance }
    }
}

struct ShowcaseLayout {
    let totalWidth: CGFloat
    let totalHeight: CGFloat
    let columns: Int
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let spacing: CGFloat
    let cornerRadius: CGFloat
    let shadowRadius: CGFloat
    let shadowY: CGFloat

    init(row: ScreenshotRow, config: ShowcaseExportConfig) {
        let count = row.templates.count
        let w = row.templateWidth
        let h = row.templateHeight

        // 2-row grid only for 8/10/12… templates — keeps the aspect balanced
        let rowCount = (count >= 8 && count % 2 == 0) ? 2 : 1
        columns = rowCount == 2 ? count / 2 : count

        spacing = round(w * config.spacingPercent / 100)
        cornerRadius = round(h * config.cornerRadiusPercent / 100)
        shadowRadius = round(h * 0.02)
        shadowY = round(h * 0.008)

        let shadowExtent = shadowRadius + shadowY
        let contentW = CGFloat(columns) * w + CGFloat(columns - 1) * spacing
        let contentH = CGFloat(rowCount) * h + CGFloat(rowCount - 1) * spacing
        let minPadH = round(w * config.paddingPercent / 100)
        let minPadV = round(h * config.paddingPercent / 200)
        let minWidth = contentW + minPadH * 2
        let minHeight = contentH + minPadV + max(minPadV, shadowExtent)

        let targetAspect = CGFloat(config.aspectRatio)
        if minWidth / minHeight > targetAspect {
            totalWidth = minWidth
            totalHeight = round(totalWidth / targetAspect)
        } else {
            totalHeight = minHeight
            totalWidth = round(totalHeight * targetAspect)
        }
        horizontalPadding = round((totalWidth - contentW) / 2)
        verticalPadding = round((totalHeight - contentH) / 2)
    }
}

struct ShowcaseRowView<Background: View>: View {
    let templateImages: [NSImage]
    let templateWidth: CGFloat
    let templateHeight: CGFloat
    let layout: ShowcaseLayout
    let background: Background
    var scale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: layout.spacing * scale) {
            ForEach(0..<gridRows, id: \.self) { rowIndex in
                HStack(spacing: layout.spacing * scale) {
                    ForEach(0..<layout.columns, id: \.self) { colIndex in
                        let index = rowIndex * layout.columns + colIndex
                        if index < templateImages.count {
                            templateImageView(templateImages[index])
                        }
                    }
                }
            }
        }
        .padding(.horizontal, layout.horizontalPadding * scale)
        .padding(.vertical, layout.verticalPadding * scale)
        .frame(width: layout.totalWidth * scale, height: layout.totalHeight * scale)
        .background(background)
        .clipped()
    }

    private var gridRows: Int {
        (templateImages.count + layout.columns - 1) / layout.columns
    }

    private func templateImageView(_ img: NSImage) -> some View {
        Image(nsImage: img)
            .resizable()
            .frame(width: templateWidth * scale, height: templateHeight * scale)
            .clipShape(RoundedRectangle(cornerRadius: layout.cornerRadius * scale, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: layout.shadowRadius * scale, x: 0, y: layout.shadowY * scale)
    }
}

enum ExportError: LocalizedError {
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .renderFailed: String(localized: "Failed to render screenshot")
        }
    }
}
