import SwiftUI
import UniformTypeIdentifiers

struct SvgPasteDialog: View {
    @Binding var isPresented: Bool
    var onConfirm: (String, CGSize) -> Void

    @State private var svgText = ""
    @State private var errorMessage: String?
    @State private var previewImage: NSImage?
    @State private var isValidSvg = false

    var body: some View {
        VStack(spacing: 12) {
            Text("Add SVG")
                .font(.headline)

            TextEditor(text: $svgText)
                .font(.system(size: 11, design: .monospaced))
                .frame(minHeight: 120)
                .border(Color.secondary.opacity(0.3))
                .onChange(of: svgText) { updatePreview() }

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

        guard trimmed.contains("<svg") else {
            previewImage = nil
            errorMessage = "Not a valid SVG — must contain an <svg> element"
            isValidSvg = false
            return
        }

        guard let data = trimmed.data(using: .utf8),
              let image = NSImage(data: data) else {
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
        let sanitized = sanitizeSvg(trimmed)
        guard let data = sanitized.data(using: .utf8),
              let image = NSImage(data: data) else {
            errorMessage = "Invalid SVG content"
            return
        }
        let size = parseSvgSize(sanitized, fallbackImage: image)
        onConfirm(sanitized, size)
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

    private func sanitizeSvg(_ svg: String) -> String {
        var result = svg
        // Remove script elements (case-insensitive)
        result = result.replacingOccurrences(
            of: "<script[^>]*>[\\s\\S]*?</script>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        // Remove event handlers (double and single quoted)
        result = result.replacingOccurrences(
            of: "\\s+on\\w+\\s*=\\s*\"[^\"]*\"",
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "\\s+on\\w+\\s*=\\s*'[^']*'",
            with: "",
            options: .regularExpression
        )
        return result
    }

    private func parseSvgSize(_ svg: String, fallbackImage: NSImage) -> CGSize {
        // Try viewBox first
        if let viewBoxMatch = svg.range(of: "viewBox\\s*=\\s*\"([^\"]+)\"", options: .regularExpression) {
            let attrValue = svg[viewBoxMatch]
            if let quoteStart = attrValue.firstIndex(of: "\""),
               let quoteEnd = attrValue[attrValue.index(after: quoteStart)...].firstIndex(of: "\"") {
                let parts = svg[attrValue.index(after: quoteStart)..<quoteEnd]
                    .split(whereSeparator: { $0 == " " || $0 == "," })
                    .compactMap { Double($0) }
                if parts.count == 4 {
                    return CGSize(width: max(parts[2], 20), height: max(parts[3], 20))
                }
            }
        }
        // Fallback to image size
        let rep = fallbackImage.representations.first
        let w = CGFloat(rep?.pixelsWide ?? Int(fallbackImage.size.width))
        let h = CGFloat(rep?.pixelsHigh ?? Int(fallbackImage.size.height))
        return CGSize(width: max(w, 20), height: max(h, 20))
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
