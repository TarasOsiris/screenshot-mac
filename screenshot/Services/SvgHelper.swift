import AppKit

enum SvgHelper {
    static func sanitize(_ svg: String) -> String {
        var result = svg.trimmingCharacters(in: .whitespacesAndNewlines)
        result = result.replacingOccurrences(
            of: "<script[^>]*>[\\s\\S]*?</script>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
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

    static func parseSize(_ svg: String, fallbackImage: NSImage) -> CGSize {
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
        let rep = fallbackImage.representations.first
        let w = CGFloat(rep?.pixelsWide ?? Int(fallbackImage.size.width))
        let h = CGFloat(rep?.pixelsHigh ?? Int(fallbackImage.size.height))
        return CGSize(width: max(w, 20), height: max(h, 20))
    }

    static func scaledSize(_ size: CGSize, maxDim: CGFloat = 400) -> CGSize {
        let scale = min(maxDim / max(size.width, 1), maxDim / max(size.height, 1), 1)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}
