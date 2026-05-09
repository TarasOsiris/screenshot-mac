import AppKit
import SwiftUI

private struct ASCAppIconView: View {
    let bundleId: String
    let size: CGFloat

    @State private var iconURL: URL?

    var body: some View {
        Group {
            if let iconURL {
                AsyncImage(url: iconURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable()
                    case .failure, .empty:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .task(id: bundleId) {
            iconURL = await AppStoreConnectIconFetcher.shared.iconURL(forBundleId: bundleId)
        }
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(Color.secondary.opacity(0.15))
            Image(systemName: "app.fill")
                .foregroundStyle(.secondary)
                .font(.system(size: size * 0.45))
        }
    }
}

struct ASCAppHeaderView: View {
    let app: ASCApp
    let subtitle: String
    var iconSize: CGFloat = 40

    var body: some View {
        HStack(spacing: 10) {
            ASCAppIconView(bundleId: app.attributes.bundleId, size: iconSize)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.attributes.name)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ASCUploadFailureDetailItem: Identifiable {
    let id = UUID()
    let message: String
}

struct ASCUploadFailureDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let details: String

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Upload failed", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.red)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Divider()

            ScrollView([.vertical, .horizontal]) {
                Text(details)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .background(Color(nsColor: .textBackgroundColor))

            Divider()

            HStack {
                Button("Copy Details") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(details, forType: .string)
                }
                Spacer()
                Button("OK") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .frame(width: 760, height: 520)
    }
}
