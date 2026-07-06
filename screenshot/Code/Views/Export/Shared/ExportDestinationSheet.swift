#if os(iOS)
import SwiftUI

/// iPad export-destination chooser: a fitted, anchorless bottom sheet (replaces a `.confirmationDialog`,
/// which renders as a stray-arrow popover on iPad when fired programmatically after a render). Selecting
/// a row consumes `pendingExport` (dismissing this sheet) and routes the rendered files to that
/// destination via `PlatformPresenter.whenReady`. Icons match `ShowcaseExportSheet.exportDestinationMenu`.
struct ExportDestinationSheet: View {
    let title: String
    let onSelect: (ExportDestination) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                row(.photos, title: "Save to Photos",
                    subtitle: "Add to your photo library", systemImage: "photo.on.rectangle")
                row(.files, title: "Save to Files",
                    subtitle: "Save into the Files app", systemImage: "folder")
                row(.share, title: "Share…",
                    subtitle: "AirDrop, Mail, Messages and more", systemImage: "square.and.arrow.up")
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .navigationTitle(Text(verbatim: title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .presentationDetents([.height(340), .medium])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(24)
    }

    @ViewBuilder
    private func row(_ destination: ExportDestination,
                     title: LocalizedStringKey,
                     subtitle: LocalizedStringKey,
                     systemImage: String) -> some View {
        Button { onSelect(destination) } label: {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .frame(width: 32, height: 32)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.section)
                .fill(Color.primary.opacity(UIMetrics.Opacity.sectionFill))
        )
        .overlay {
            RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.section)
                .stroke(Color(.separator).opacity(UIMetrics.Opacity.sectionBorder),
                        lineWidth: UIMetrics.BorderWidth.hairline)
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
