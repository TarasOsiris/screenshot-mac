import SwiftUI
import UniformTypeIdentifiers

struct TemplateControlBar: View {
    @Binding var template: ScreenshotTemplate
    let row: ScreenshotRow
    let index: Int
    let zoom: CGFloat
    var screenshotImages: [String: NSImage] = [:]
    var onSave: () -> Void
    var onDelete: () -> Void
    @State private var isDeletingTemplate = false
    @State private var showBackgroundPopover = false

    private var canDelete: Bool { row.templates.count > 1 }

    var body: some View {
        HStack(spacing: 6) {
            templateActionButton("eye", tooltip: "Preview") {
                previewScreenshot()
            }
            templateActionButton("arrow.down.circle", tooltip: "Download") {
                downloadScreenshot()
            }

            // Background override button
            Button {
                showBackgroundPopover = true
            } label: {
                HStack(spacing: 3) {
                    if template.overrideBackground {
                        template.backgroundFill
                            .frame(width: 12, height: 12)
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .strokeBorder(.secondary.opacity(0.5), lineWidth: 0.5)
                            )
                    } else {
                        Image(systemName: "paintbrush")
                            .font(.system(size: 11))
                    }
                }
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .focusable(false)
            .foregroundStyle(template.overrideBackground ? .primary : .secondary)
            .help("Background override")
            .popover(isPresented: $showBackgroundPopover, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(
                        "Override background",
                        isOn: $template.overrideBackground.onSet { onSave() }
                    )
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(size: 12))

                    if template.overrideBackground {
                        Divider()
                        BackgroundEditor(
                            backgroundStyle: $template.backgroundStyle,
                            bgColor: $template.bgColor,
                            gradientConfig: $template.gradientConfig,
                            compact: true,
                            onChanged: onSave
                        )
                    }
                }
                .padding(12)
                .frame(width: 240)
            }

            Spacer()
            Menu {
                Button("Preview", systemImage: "eye") {
                    previewScreenshot()
                }
                Button("Download PNG...", systemImage: "square.and.arrow.down") {
                    downloadScreenshot()
                }
                if canDelete {
                    Divider()
                    Button("Delete Screenshot", systemImage: "trash", role: .destructive) {
                        isDeletingTemplate = true
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 12))
                    .frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton)
            .help("More actions")
        }
        .controlSize(.small)
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
        .buttonStyle(.borderless)
        .focusable(false)
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
