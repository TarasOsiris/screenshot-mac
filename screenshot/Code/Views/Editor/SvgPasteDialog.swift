import SwiftUI
import UniformTypeIdentifiers

struct SvgPasteDialog: View {
    @Binding var isPresented: Bool
    var onConfirm: (String, CGSize, Bool, Color) -> Void

    @State private var svgText = ""
    @State private var errorMessage: String?
    @State private var previewImage: NSImage?
    @State private var isValidSvg = false
    @State private var useColorOverride = false
    @State private var overrideColor: Color = .white
    @State private var selectedPresetId: String?
    @State private var suppressTextChangeReset = false

    var body: some View {
        VStack(spacing: 12) {
            Text("Add SVG")
                .font(.headline)

            SvgPresetPicker(
                selectedId: selectedPresetId,
                overrideColor: useColorOverride ? overrideColor : nil,
                onPick: applyPreset
            )

            ZStack(alignment: .topLeading) {
                TextEditor(text: $svgText)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(minHeight: 120)
                    .border(Color.secondary.opacity(0.3))
                    .onChange(of: svgText) {
                        if suppressTextChangeReset {
                            suppressTextChangeReset = false
                        } else {
                            selectedPresetId = nil
                        }
                        updatePreview()
                    }

                if svgText.isEmpty {
                    Text("Paste your SVG here...")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 7)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }

            // Preview
            if let previewImage {
                Image(nsImage: previewImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 100)
                    .background(
                        CheckerboardPattern()
                            .foregroundStyle(Color.secondary.opacity(0.15))
                    )
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 8) {
                Toggle("Override color", isOn: $useColorOverride)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: useColorOverride) { updatePreview() }

                ColorPicker("", selection: $overrideColor, supportsOpacity: false)
                    .labelsHidden()
                    .disabled(!useColorOverride)
                    .onChange(of: overrideColor) {
                        if useColorOverride { updatePreview() }
                    }
            }

            HStack {
                Button("Import File...") {
                    importFile()
                }

                Spacer()

                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Add") {
                    addSvg()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValidSvg)
            }
        }
        .padding()
        .frame(width: 480)
    }

    private func applyPreset(_ preset: SvgPreset) {
        suppressTextChangeReset = true
        selectedPresetId = preset.id
        svgText = preset.sanitizedContent
    }

    private func updatePreview() {
        let trimmed = svgText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            previewImage = nil
            errorMessage = nil
            isValidSvg = false
            return
        }

        let maxSvgSize = 512 * 1024 // 512 KB
        guard trimmed.utf8.count <= maxSvgSize else {
            previewImage = nil
            errorMessage = String(localized: "SVG content is too large (max 512 KB)")
            isValidSvg = false
            return
        }

        guard trimmed.contains("<svg") else {
            previewImage = nil
            errorMessage = String(localized: "Not a valid SVG — must contain an <svg> element")
            isValidSvg = false
            return
        }

        guard let image = SvgHelper.renderImage(from: trimmed, useColor: useColorOverride, color: overrideColor) else {
            previewImage = nil
            errorMessage = String(localized: "Could not render SVG — check for syntax errors")
            isValidSvg = false
            return
        }

        previewImage = image
        errorMessage = nil
        isValidSvg = true
    }

    private func addSvg() {
        let trimmed = svgText.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitized = SvgHelper.sanitize(trimmed)
        guard let data = sanitized.data(using: .utf8),
              let image = NSImage(data: data) else {
            errorMessage = String(localized: "Invalid SVG content")
            return
        }
        let size = SvgHelper.parseSize(sanitized, fallbackImage: image)
        onConfirm(sanitized, size, useColorOverride, overrideColor)
        isPresented = false
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "svg") ?? .xml]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        if let content = try? String(contentsOf: url, encoding: .utf8) {
            svgText = content
            errorMessage = nil
            updatePreview()
        }
    }

}

private struct SvgPresetPicker: View {
    let selectedId: String?
    let overrideColor: Color?
    let onPick: (SvgPreset) -> Void

    private let presets = SvgPresetCatalog.all
    private static let thumbSize: CGFloat = 44
    private let columns = Array(repeating: GridItem(.fixed(SvgPresetPicker.thumbSize), spacing: 6), count: 8)

    var body: some View {
        if presets.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Presets")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(presets) { preset in
                            SvgPresetThumbnail(
                                preset: preset,
                                isSelected: preset.id == selectedId,
                                size: Self.thumbSize,
                                overrideColor: overrideColor
                            )
                            .onTapGesture { onPick(preset) }
                        }
                    }
                    .padding(4)
                }
                .frame(maxHeight: 160)
                .background(Color.primary.opacity(UIMetrics.Opacity.sectionFill))
                .clipShape(RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.card))
            }
        }
    }
}

private struct SvgPresetThumbnail: View {
    let preset: SvgPreset
    let isSelected: Bool
    let size: CGFloat
    let overrideColor: Color?

    @State private var image: NSImage?

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.chip) }

    var body: some View {
        ZStack {
            shape.fill(Color.primary.opacity(UIMetrics.Opacity.sectionFill))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(4)
            }
        }
        .frame(width: size, height: size)
        .overlay(
            shape.strokeBorder(
                isSelected ? Color.accentColor : UIMetrics.Stroke.subtle,
                lineWidth: isSelected ? UIMetrics.BorderWidth.emphasis : UIMetrics.BorderWidth.standard
            )
        )
        .task(id: thumbnailKey) { await renderThumbnail() }
    }

    /// Thumbnails always recolor — the bundled SVGs use a dim gray that looks washed out
    /// against the picker background, especially in dark mode. When the editor's override
    /// color is unset, fall back to `.primary` so shapes adapt to light/dark appearance.
    private var thumbnailTint: Color { overrideColor ?? .primary }

    private var thumbnailKey: String { preset.id + "|" + thumbnailTint.hexString }

    private func renderThumbnail() async {
        let rendered = SvgHelper.renderImage(
            from: preset.sanitizedContent,
            useColor: true,
            color: thumbnailTint
        )
        await MainActor.run { self.image = rendered }
    }
}

struct CheckerboardPattern: View {
    var body: some View {
        Canvas { context, size in
            let cellSize: CGFloat = 8
            for row in 0..<Int(ceil(size.height / cellSize)) {
                for col in 0..<Int(ceil(size.width / cellSize)) {
                    if (row + col).isMultiple(of: 2) {
                        context.fill(
                            Path(CGRect(x: CGFloat(col) * cellSize, y: CGFloat(row) * cellSize, width: cellSize, height: cellSize)),
                            with: .foreground
                        )
                    }
                }
            }
        }
    }
}
