import Foundation
import SwiftUI

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
