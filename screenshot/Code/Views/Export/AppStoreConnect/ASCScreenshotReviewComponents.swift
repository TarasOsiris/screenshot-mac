import SwiftUI

struct ASCScreenshotStatusCapsule: View {
    let status: ASCScreenshotDiffStatus
    let count: Int

    var body: some View {
        Label("\(count) \(status.label)", systemImage: status.icon)
            .font(.caption)
            .foregroundStyle(status.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.color.opacity(0.1), in: Capsule())
    }
}

struct ASCScreenshotDiffThumbnail: View {
    let item: ASCScreenshotDiffItem
    let proposed: Bool
    let onPreview: (() -> Void)?

    @ViewBuilder
    var body: some View {
        if let onPreview {
            Button(action: onPreview) {
                content
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityDescription)
            .accessibilityHint("Quick Look")
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityDescription)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 5) {
            Group {
                if let image = previewImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "photo.badge.exclamationmark")
                        Text("Preview unavailable")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .frame(width: 116, height: 150)
            .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 7))
            .clipShape(.rect(cornerRadius: 7))

            HStack(spacing: 4) {
                Text("#\(displayIndex)")
                    .monospacedDigit()
                Image(systemName: item.status.icon)
                Text(item.status.label)
            }
            .font(.caption2.bold())
            .foregroundStyle(item.status.color)
        }
        .frame(width: 116)
    }

    private var previewImage: NSImage? {
        guard let data = proposed ? item.localAsset?.previewData : item.remoteAsset?.previewData else { return nil }
        return NSImage(data: data)
    }

    private var displayIndex: Int {
        (proposed ? item.proposedIndex : item.originalIndex).map { $0 + 1 } ?? 0
    }

    private var accessibilityDescription: String {
        let source = proposed ? String(localized: "Proposed") : String(localized: "Current App Store")
        return "\(source) screenshot \(displayIndex), \(item.status.label)"
    }
}

extension ASCScreenshotDiffStatus {
    var label: String {
        switch self {
        case .unchanged: String(localized: "Unchanged")
        case .moved: String(localized: "Moved")
        case .new: String(localized: "New")
        case .removed: String(localized: "Removed")
        }
    }

    var icon: String {
        switch self {
        case .unchanged: "checkmark.circle.fill"
        case .moved: "arrow.left.arrow.right.circle.fill"
        case .new: "plus.circle.fill"
        case .removed: "minus.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .unchanged: .green
        case .moved: .blue
        case .new: .mint
        case .removed: .orange
        }
    }
}
