import SwiftUI
import UniformTypeIdentifiers

struct TemplateControlBar: View {
    @Binding var template: ScreenshotTemplate
    let row: ScreenshotRow
    let index: Int
    let zoom: CGFloat
    var screenshotImages: [String: NSImage] = [:]
    var localeState: LocaleState = .default
    var canMoveLeft: Bool = false
    var canMoveRight: Bool = false
    var onMoveLeft: () -> Void = {}
    var onMoveRight: () -> Void = {}
    var onSave: () -> Void
    var onPickBackgroundImage: (() -> Void)?
    var onRemoveBackgroundImage: (() -> Void)?
    var onDropBackgroundImage: ((NSImage) -> Void)? = nil
    var onDuplicate: () -> Void = {}
    var onDelete: () -> Void
    var onLoadFullResImages: (() -> [String: NSImage])? = nil
    @AppStorage("confirmBeforeDeleting") private var confirmBeforeDeleting = true
    @State private var isDeletingTemplate = false
    @State private var showBackgroundPopover = false
    @State private var renderError: String?

    private var canDelete: Bool { row.templates.count > 1 }
    private var isCompact: Bool { row.displayWidth(zoom: zoom) < 200 }
    private var backgroundPreviewImage: NSImage? {
        template.backgroundImageConfig.fileName.flatMap { screenshotImages[$0] }
    }
    private var isImageBackgroundMissing: Bool {
        template.overrideBackground &&
        template.backgroundStyle == .image &&
        backgroundPreviewImage == nil
    }
    private var backgroundButtonHelp: String {
        if isImageBackgroundMissing {
            return "Background override (image not selected)"
        }
        return "Background override"
    }
    private var backgroundButtonStyle: AnyShapeStyle {
        if isImageBackgroundMissing {
            return AnyShapeStyle(Color.orange)
        }
        return template.overrideBackground
            ? AnyShapeStyle(.primary)
            : AnyShapeStyle(.secondary)
    }

    var body: some View {
        HStack(spacing: 6) {
            if !isCompact {
                ActionButton(icon: "eye", tooltip: "Preview") {
                    previewScreenshot()
                }
                ActionButton(icon: "arrow.down.circle", tooltip: "Download") {
                    downloadScreenshot()
                }
                ActionButton(icon: "chevron.left", tooltip: "Move left", disabled: !canMoveLeft) {
                    onMoveLeft()
                }
                ActionButton(icon: "chevron.right", tooltip: "Move right", disabled: !canMoveRight) {
                    onMoveRight()
                }
            }

            // Background override button
            Button {
                showBackgroundPopover = true
            } label: {
                HStack(spacing: 3) {
                    if template.overrideBackground {
                        if template.backgroundStyle == .image {
                            if let image = backgroundPreviewImage {
                                Image(nsImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 12, height: 12)
                                    .clipShape(RoundedRectangle(cornerRadius: 2))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 2)
                                            .strokeBorder(.secondary.opacity(0.5), lineWidth: 0.5)
                                    )
                            } else {
                                Image(systemName: "photo.badge.plus")
                                    .font(.system(size: 10))
                                    .frame(width: 12, height: 12)
                            }
                        } else {
                            template.backgroundFillView()
                                .frame(width: 12, height: 12)
                                .clipShape(RoundedRectangle(cornerRadius: 2))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 2)
                                        .strokeBorder(.secondary.opacity(0.5), lineWidth: 0.5)
                                )
                        }
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
            .foregroundStyle(backgroundButtonStyle)
            .help(backgroundButtonHelp)
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
                            backgroundImageConfig: $template.backgroundImageConfig,
                            backgroundImage: backgroundPreviewImage,
                            compact: true,
                            onChanged: onSave,
                            onPickImage: onPickBackgroundImage,
                            onRemoveImage: onRemoveBackgroundImage,
                            onDropImage: onDropBackgroundImage
                        )
                    }
                }
                .padding(12)
                .frame(width: 260)
            }

            Spacer()
            if canDelete {
                ActionButton(icon: "trash", tooltip: "Delete Screenshot", isDestructive: true) {
                    confirmDeleteTemplate()
                }
            }
            Menu {
                Button("Quick Look", systemImage: "eye") {
                    previewScreenshot()
                }
                Button("Save as PNG...", systemImage: "square.and.arrow.down") {
                    downloadScreenshot()
                }
                Button("Move Left", systemImage: "chevron.left") {
                    onMoveLeft()
                }
                .disabled(!canMoveLeft)
                Button("Move Right", systemImage: "chevron.right") {
                    onMoveRight()
                }
                .disabled(!canMoveRight)
                Button("Duplicate Screenshot", systemImage: "plus.square.on.square") {
                    onDuplicate()
                }
                if canDelete {
                    Divider()
                    Button("Delete Screenshot", systemImage: "trash", role: .destructive) {
                        confirmDeleteTemplate()
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 12))
                    .frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("More actions")
        }
        .controlSize(.small)
        .padding(.horizontal, 4)
        .frame(width: row.displayWidth(zoom: zoom))
        .overlay(alignment: .leading) {
            if index > 0 {
                Rectangle()
                    .fill(.separator)
                    .frame(width: 1, height: 20)
            }
        }
        .alert("Delete Screenshot", isPresented: $isDeletingTemplate) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this screenshot?")
        }
        .alert("Render Failed", isPresented: .init(
            get: { renderError != nil },
            set: { if !$0 { renderError = nil } }
        )) {
            Button("OK") { renderError = nil }
        } message: {
            Text(renderError ?? "")
        }
    }

    private func confirmDeleteTemplate() {
        if confirmBeforeDeleting {
            isDeletingTemplate = true
        } else {
            onDelete()
        }
    }

    private func previewScreenshot() {
        guard let pngData = ExportService.renderTemplatePNG(index: index, row: row, screenshotImages: screenshotImages, localeState: localeState) else {
            renderError = "Could not render screenshot for preview."
            return
        }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("screenshot-\(index + 1)-\(localeState.activeLocaleCode).png")
        do {
            try pngData.write(to: tempURL)
        } catch {
            renderError = "Could not write preview file: \(error.localizedDescription)"
            return
        }
        QuickLookCoordinator.shared.preview(imageAt: tempURL)
    }

    private func downloadScreenshot() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "screenshot-\(index + 1).png"
        panel.allowedContentTypes = [.png]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        let exportImages = onLoadFullResImages?() ?? screenshotImages
        guard let pngData = ExportService.renderTemplatePNG(index: index, row: row, screenshotImages: exportImages, localeState: localeState) else {
            renderError = "Could not render screenshot."
            return
        }
        do {
            try pngData.write(to: url)
        } catch {
            renderError = "Could not save file: \(error.localizedDescription)"
        }
    }
}
