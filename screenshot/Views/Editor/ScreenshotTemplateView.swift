import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ScreenshotTemplateView: View {
    let template: ScreenshotTemplate
    let displayWidth: CGFloat
    let displayHeight: CGFloat
    let templateWidth: CGFloat
    let templateHeight: CGFloat
    var bgColor: Color = .blue
    var index: Int = 0
    var canDelete: Bool = false
    var onDelete: (() -> Void)?
    var body: some View {
        VStack(spacing: 0) {
            // Screenshot canvas
            RoundedRectangle(cornerRadius: 8)
                .fill(bgColor.gradient)
                .frame(width: displayWidth, height: displayHeight)
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)

            // Control bar
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
                        onDelete?()
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 6)
            .frame(width: displayWidth)
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

    private func renderPNGData() -> Data? {
        let view = Rectangle()
            .fill(bgColor.gradient)
            .frame(width: templateWidth, height: templateHeight)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1.0
        renderer.proposedSize = ProposedViewSize(width: templateWidth, height: templateHeight)

        guard let cgImage = renderer.cgImage else { return nil }
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: templateWidth, height: templateHeight))

        guard let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return nil }

        return pngData
    }

    private func previewScreenshot() {
        guard let pngData = renderPNGData() else { return }

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

        guard let pngData = renderPNGData() else { return }
        try? pngData.write(to: url)
    }
}
