import Foundation
import SwiftUI

// MARK: - Showcase SwiftUI View

struct ShowcaseRowView: View {
    let templateImages: [NSImage]
    let templateWidth: CGFloat
    let templateHeight: CGFloat
    let columns: Int
    let spacing: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let cornerRadius: CGFloat
    let shadowRadius: CGFloat
    let shadowY: CGFloat
    let backgroundColor: Color

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(0..<rows, id: \.self) { rowIndex in
                HStack(spacing: spacing) {
                    ForEach(0..<columns, id: \.self) { colIndex in
                        let index = rowIndex * columns + colIndex
                        if index < templateImages.count {
                            templateImageView(templateImages[index])
                        }
                    }
                }
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(backgroundColor)
    }

    private var rows: Int {
        (templateImages.count + columns - 1) / columns
    }

    private func templateImageView(_ img: NSImage) -> some View {
        Image(nsImage: img)
            .resizable()
            .frame(width: templateWidth, height: templateHeight)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: shadowRadius, x: 0, y: shadowY)
    }
}

enum ExportError: LocalizedError {
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .renderFailed: "Failed to render screenshot"
        }
    }
}
