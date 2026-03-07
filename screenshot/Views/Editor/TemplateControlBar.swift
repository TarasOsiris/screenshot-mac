import SwiftUI
import UniformTypeIdentifiers

struct TemplateControlBar: View {
    let row: ScreenshotRow
    let index: Int
    let zoom: CGFloat
    var screenshotImages: [String: NSImage] = [:]
    var onDelete: () -> Void
    @State private var isDeletingTemplate = false

    private var canDelete: Bool { row.templates.count > 1 }

    var body: some View {
        HStack(spacing: 6) {
            templateActionButton("eye", tooltip: "Preview") {
                previewScreenshot()
            }
            templateActionButton("arrow.down.circle", tooltip: "Download") {
                downloadScreenshot()
            }
            Spacer()
            if canDelete {
                templateActionButton("trash", tooltip: "Delete") {
                    isDeletingTemplate = true
                }
            }
        }
        .padding(.horizontal, 4)
        .frame(width: row.displayWidth(zoom: zoom))
        .alert("Delete Screenshot", isPresented: $isDeletingTemplate) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this screenshot?")
        }
    }

    private func templateActionButton(_ icon: String, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(tooltip)
    }

    private func previewScreenshot() {
        guard let pngData = ExportService.renderTemplatePNG(index: index, row: row, screenshotImages: screenshotImages) else { return }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("screenshot-\(index + 1).png")
        try? pngData.write(to: tempURL)
        QuickLookCoordinator.shared.preview(imageAt: tempURL)
    }

    private func downloadScreenshot() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "screenshot-\(index + 1).png"
        panel.allowedContentTypes = [.png]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        guard let pngData = ExportService.renderTemplatePNG(index: index, row: row, screenshotImages: screenshotImages) else { return }
        try? pngData.write(to: url)
    }
}
