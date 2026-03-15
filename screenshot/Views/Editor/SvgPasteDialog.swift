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

    var body: some View {
        VStack(spacing: 12) {
            Text("Add SVG")
                .font(.headline)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $svgText)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(minHeight: 120)
                    .border(Color.secondary.opacity(0.3))
                    .onChange(of: svgText) { updatePreview() }

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
        .frame(width: 400)
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
            errorMessage = "SVG content is too large (max 512 KB)"
            isValidSvg = false
            return
        }

        guard trimmed.contains("<svg") else {
            previewImage = nil
            errorMessage = "Not a valid SVG — must contain an <svg> element"
            isValidSvg = false
            return
        }

        guard let image = SvgHelper.renderImage(from: trimmed, useColor: useColorOverride, color: overrideColor) else {
            previewImage = nil
            errorMessage = "Could not render SVG — check for syntax errors"
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
            errorMessage = "Invalid SVG content"
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
