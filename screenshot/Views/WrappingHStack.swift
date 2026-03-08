import SwiftUI

struct WrappingHStack: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 4

    struct Cache {
        var sizes: [CGSize]
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache(sizes: subviews.map { $0.sizeThatFits(.unspecified) })
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache = makeCache(subviews: subviews)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        guard !cache.sizes.isEmpty else { return .zero }

        let rows = computeRows(sizes: cache.sizes, maxWidth: proposal.width ?? .infinity)
        let rowHeights = rows.map { row in
            row.map { cache.sizes[$0].height }.max() ?? 0
        }
        let rowWidths = rows.map { row in
            row.enumerated().reduce(CGFloat(0)) { partial, pair in
                partial + (pair.offset > 0 ? spacing : 0) + cache.sizes[pair.element].width
            }
        }

        let height = rowHeights.enumerated().reduce(CGFloat(0)) { total, pair in
            total + pair.element + (pair.offset > 0 ? lineSpacing : 0)
        }
        let width = proposal.width ?? (rowWidths.max() ?? 0)
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        // Recompute if proposal width changed (affects row distribution)
        let sizes = cache.sizes
        let rows = computeRows(sizes: sizes, maxWidth: proposal.width ?? bounds.width)
        let rowHeights = rows.map { row in
            row.map { sizes[$0].height }.max() ?? 0
        }

        var y = bounds.minY
        for (rowIndex, row) in rows.enumerated() {
            let rowHeight = rowHeights[rowIndex]
            var x = bounds.minX

            for index in row {
                let size = sizes[index]
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (rowHeight - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += rowHeight + lineSpacing
        }
    }

    private func computeRows(sizes: [CGSize], maxWidth: CGFloat = .infinity) -> [[Int]] {
        var rows: [[Int]] = [[]]
        var currentWidth: CGFloat = 0

        for (index, size) in sizes.enumerated() {
            let neededWidth = currentWidth > 0 ? size.width + spacing : size.width

            if currentWidth + neededWidth > maxWidth && !rows[rows.count - 1].isEmpty {
                rows.append([index])
                currentWidth = size.width
            } else {
                rows[rows.count - 1].append(index)
                currentWidth += neededWidth
            }
        }
        return rows
    }
}
