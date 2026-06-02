#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SwiftUI
import UniformTypeIdentifiers

enum PickedBackground {
    case image(NSImage)
    case svg(String)
}

enum SvgHelper {
    /// Prompts the user for an image or SVG file and returns the picked content.
    /// Returns nil if the user cancels or the file cannot be loaded.
    @MainActor
    static func pickImageOrSvg() -> PickedBackground? {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .svg]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        if url.pathExtension.lowercased() == "svg",
           let sanitized = loadAndSanitize(from: url) {
            return .svg(sanitized)
        }
        guard let image = NSImage.fromSecurityScopedURL(url) else { return nil }
        return .image(image)
        #else
        // iPad: image/SVG import via PhotosPicker/fileImporter is deferred to a follow-up.
        return nil
        #endif
    }

    /// Reads an SVG file from a URL, converts to String, and sanitizes it.
    /// Returns nil for non-SVG files.
    static func loadAndSanitize(from url: URL) -> String? {
        guard url.pathExtension.lowercased() == "svg",
              let data = try? Data(contentsOf: url),
              let raw = String(data: data, encoding: .utf8) else { return nil }
        return sanitize(raw)
    }

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

    /// Parses the SVG's viewBox to get its natural size. Returns nil if no viewBox is found.
    static func parseViewBoxSize(_ svg: String) -> CGSize? {
        guard let viewBoxMatch = svg.range(of: "viewBox\\s*=\\s*[\"']([^\"']+)[\"']", options: .regularExpression) else { return nil }
        let attrValue = svg[viewBoxMatch]
        guard let quoteStart = attrValue.firstIndex(where: { $0 == "\"" || $0 == "'" }),
              quoteStart < attrValue.endIndex,
              let quoteEnd = attrValue[attrValue.index(after: quoteStart)...].firstIndex(where: { $0 == "\"" || $0 == "'" }) else { return nil }
        let parts = svg[attrValue.index(after: quoteStart)..<quoteEnd]
            .split(whereSeparator: { $0 == " " || $0 == "," })
            .compactMap { Double($0) }
        guard parts.count == 4 else { return nil }
        return CGSize(width: max(parts[2], 20), height: max(parts[3], 20))
    }

    static func parseSize(_ svg: String, fallbackImage: NSImage) -> CGSize {
        if let size = parseViewBoxSize(svg) { return size }
        let rep = fallbackImage.representations.first
        let w = CGFloat(rep?.pixelsWide ?? Int(fallbackImage.size.width))
        let h = CGFloat(rep?.pixelsHigh ?? Int(fallbackImage.size.height))
        return CGSize(width: max(w, 20), height: max(h, 20))
    }

    static func scaledSize(_ size: CGSize, maxDim: CGFloat = 400, minDim: CGFloat = 256) -> CGSize {
        let largest = max(size.width, size.height, 1)
        let target = min(max(largest, minDim), maxDim)
        let scale = target / largest
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    /// Rewrites `fill`/`stroke` attributes in the SVG so the resulting image renders in `color`.
    /// Handles both single- and double-quoted attributes (templates and pasted SVGs use either).
    /// Preserves `fill="none"` / `stroke="none"` so non-filled paths stay unfilled.
    static func applyColor(_ color: Color, to svgContent: String) -> String {
        let hex = color.hexString
        var svg = svgContent
        for attr in ["fill", "stroke"] {
            svg = svg.replacingOccurrences(
                of: "\(attr)\\s*=\\s*\"(?!none\")[^\"]*\"",
                with: "\(attr)=\"\(hex)\"",
                options: .regularExpression
            )
            svg = svg.replacingOccurrences(
                of: "\(attr)\\s*=\\s*'(?!none')[^']*'",
                with: "\(attr)=\"\(hex)\"",
                options: .regularExpression
            )
        }
        // Set fill on the <svg> tag so elements without an explicit fill inherit the color
        if svg.range(of: "<svg\\b[^>]*\\bfill\\s*=", options: .regularExpression) == nil {
            svg = svg.replacingOccurrences(
                of: "<svg\\b",
                with: "<svg fill=\"\(hex)\"",
                options: .regularExpression
            )
        }
        return svg
    }

    static func renderImage(from svgContent: String, useColor: Bool, color: Color, targetSize: CGSize? = nil) -> NSImage? {
        let svg = useColor ? applyColor(color, to: svgContent) : svgContent
        guard let data = svg.data(using: .utf8) else { return nil }
        #if os(macOS)
        guard let baseImage = NSImage(data: data) else { return nil }

        guard let targetSize, targetSize.width > 0, targetSize.height > 0 else {
            return baseImage
        }
        let pixelW = Int(targetSize.width)
        let pixelH = Int(targetSize.height)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelW,
            pixelsHigh: pixelH,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return baseImage }
        rep.size = targetSize
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        baseImage.draw(in: NSRect(origin: .zero, size: targetSize),
                       from: .zero, operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()
        let result = NSImage(size: targetSize)
        result.addRepresentation(rep)
        return result
        #else
        if let baseImage = UIImage(data: data) {
            guard let targetSize, targetSize.width > 0, targetSize.height > 0 else {
                return baseImage
            }
            return PlatformImageRenderer.image(size: targetSize) {
                baseImage.draw(in: CGRect(origin: .zero, size: targetSize))
            }
        }
        return IOSSVGRenderer.render(svg, targetSize: targetSize)
        #endif
    }
}

#if os(iOS)
private enum IOSSVGRenderer {
    static func render(_ svg: String, targetSize: CGSize?) -> UIImage? {
        guard let data = svg.data(using: .utf8) else { return nil }
        let parser = SVGDocumentParser()
        guard let document = parser.parse(data: data) else { return nil }
        let sourceSize = document.viewBox.size
        let outputSize = targetSize ?? sourceSize
        guard outputSize.width > 0, outputSize.height > 0,
              sourceSize.width > 0, sourceSize.height > 0 else { return nil }

        return PlatformImageRenderer.image(size: outputSize) {
            guard let context = UIGraphicsGetCurrentContext() else { return }
            context.saveGState()
            context.scaleBy(x: outputSize.width / sourceSize.width, y: outputSize.height / sourceSize.height)
            context.translateBy(x: -document.viewBox.minX, y: -document.viewBox.minY)
            for element in document.elements {
                element.draw(in: context)
            }
            context.restoreGState()
        }
    }
}

private struct SVGDocument {
    let viewBox: CGRect
    let elements: [SVGElement]
}

private struct SVGElement {
    var path: UIBezierPath
    var fillColor: UIColor?
    var strokeColor: UIColor?
    var strokeWidth: CGFloat
    var usesEvenOddFill: Bool

    func draw(in context: CGContext) {
        context.saveGState()
        path.usesEvenOddFillRule = usesEvenOddFill
        if let fillColor {
            fillColor.setFill()
            path.fill()
        }
        if let strokeColor, strokeWidth > 0 {
            strokeColor.setStroke()
            path.lineWidth = strokeWidth
            path.stroke()
        }
        context.restoreGState()
    }
}

private final class SVGDocumentParser: NSObject, XMLParserDelegate {
    private var elements: [SVGElement] = []
    private var rootSize = CGSize(width: 256, height: 256)
    private var rootViewBox: CGRect?
    private var inheritedFill: UIColor?
    private var inheritedStroke: UIColor?

    func parse(data: Data) -> SVGDocument? {
        elements = []
        rootSize = CGSize(width: 256, height: 256)
        rootViewBox = nil
        inheritedFill = nil
        inheritedStroke = nil

        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse(), !elements.isEmpty else { return nil }
        let viewBox = rootViewBox ?? CGRect(origin: .zero, size: rootSize)
        return SVGDocument(viewBox: viewBox, elements: elements)
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = elementName.lowercased()
        let attributes = mergedStyleAttributes(attributeDict)

        if name == "svg" {
            rootSize = CGSize(
                width: SVGLengthParser.value(attributes["width"]) ?? rootSize.width,
                height: SVGLengthParser.value(attributes["height"]) ?? rootSize.height
            )
            rootViewBox = SVGLengthParser.viewBox(attributes["viewBox"] ?? attributes["viewbox"])
            inheritedFill = SVGColorParser.color(attributes["fill"])
            inheritedStroke = SVGColorParser.color(attributes["stroke"])
            return
        }

        guard let path = makePath(for: name, attributes: attributes) else { return }
        let opacity = SVGLengthParser.value(attributes["opacity"]) ?? 1
        let fillOpacity = opacity * (SVGLengthParser.value(attributes["fill-opacity"]) ?? 1)
        let strokeOpacity = opacity * (SVGLengthParser.value(attributes["stroke-opacity"]) ?? 1)
        let fill = SVGColorParser.color(attributes["fill"]) ?? inheritedFill
        let stroke = SVGColorParser.color(attributes["stroke"]) ?? inheritedStroke
        let strokeWidth = SVGLengthParser.value(attributes["stroke-width"]) ?? 1
        let fillRule = attributes["fill-rule"]?.lowercased()

        elements.append(SVGElement(
            path: path,
            fillColor: fill?.withAlphaComponent(max(0, min(fillOpacity, 1))),
            strokeColor: stroke?.withAlphaComponent(max(0, min(strokeOpacity, 1))),
            strokeWidth: strokeWidth,
            usesEvenOddFill: fillRule == "evenodd"
        ))
    }

    private func mergedStyleAttributes(_ attributes: [String: String]) -> [String: String] {
        var result = attributes
        guard let style = attributes["style"] else { return result }
        for pair in style.split(separator: ";") {
            let parts = pair.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if parts.count == 2, !parts[0].isEmpty {
                result[parts[0]] = parts[1]
            }
        }
        return result
    }

    private func makePath(for name: String, attributes: [String: String]) -> UIBezierPath? {
        switch name {
        case "path":
            guard let d = attributes["d"] else { return nil }
            return SVGPathParser(d).parse()
        case "rect":
            let x = SVGLengthParser.value(attributes["x"]) ?? 0
            let y = SVGLengthParser.value(attributes["y"]) ?? 0
            let width = SVGLengthParser.value(attributes["width"]) ?? 0
            let height = SVGLengthParser.value(attributes["height"]) ?? 0
            let radius = max(SVGLengthParser.value(attributes["rx"]) ?? 0, SVGLengthParser.value(attributes["ry"]) ?? 0)
            let rect = CGRect(x: x, y: y, width: width, height: height)
            return radius > 0 ? UIBezierPath(roundedRect: rect, cornerRadius: radius) : UIBezierPath(rect: rect)
        case "circle":
            let r = SVGLengthParser.value(attributes["r"]) ?? 0
            let cx = SVGLengthParser.value(attributes["cx"]) ?? 0
            let cy = SVGLengthParser.value(attributes["cy"]) ?? 0
            return UIBezierPath(ovalIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        case "ellipse":
            let rx = SVGLengthParser.value(attributes["rx"]) ?? 0
            let ry = SVGLengthParser.value(attributes["ry"]) ?? 0
            let cx = SVGLengthParser.value(attributes["cx"]) ?? 0
            let cy = SVGLengthParser.value(attributes["cy"]) ?? 0
            return UIBezierPath(ovalIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
        case "line":
            let path = UIBezierPath()
            path.move(to: CGPoint(x: SVGLengthParser.value(attributes["x1"]) ?? 0, y: SVGLengthParser.value(attributes["y1"]) ?? 0))
            path.addLine(to: CGPoint(x: SVGLengthParser.value(attributes["x2"]) ?? 0, y: SVGLengthParser.value(attributes["y2"]) ?? 0))
            return path
        case "polygon", "polyline":
            guard let points = attributes["points"] else { return nil }
            let values = SVGLengthParser.numberList(points)
            guard values.count >= 4 else { return nil }
            let path = UIBezierPath()
            path.move(to: CGPoint(x: values[0], y: values[1]))
            var index = 2
            while index + 1 < values.count {
                path.addLine(to: CGPoint(x: values[index], y: values[index + 1]))
                index += 2
            }
            if name == "polygon" { path.close() }
            return path
        default:
            return nil
        }
    }
}

private enum SVGLengthParser {
    static func value(_ raw: String?) -> CGFloat? {
        guard let raw else { return nil }
        return numberList(raw).first
    }

    static func viewBox(_ raw: String?) -> CGRect? {
        guard let raw else { return nil }
        let values = numberList(raw)
        guard values.count == 4 else { return nil }
        return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
    }

    static func numberList(_ raw: String) -> [CGFloat] {
        var values: [CGFloat] = []
        var token = ""
        var previous: Character?
        for char in raw {
            let startsSignedNumber = (char == "-" || char == "+") && previous != nil && previous != "e" && previous != "E"
            if char.isWhitespace || char == "," || startsSignedNumber {
                if let value = Double(token) {
                    values.append(CGFloat(value))
                }
                token = startsSignedNumber ? String(char) : ""
            } else if char.isNumber || char == "." || char == "-" || char == "+" || char == "e" || char == "E" {
                token.append(char)
            } else if !token.isEmpty {
                if let value = Double(token) {
                    values.append(CGFloat(value))
                }
                token = ""
            }
            previous = char
        }
        if let value = Double(token) {
            values.append(CGFloat(value))
        }
        return values
    }
}

private enum SVGColorParser {
    static func color(_ raw: String?) -> UIColor? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty, value != "none", value != "transparent" else { return nil }

        if value.hasPrefix("#") {
            return hexColor(String(value.dropFirst()))
        }
        if value.hasPrefix("rgb") {
            return rgbColor(value)
        }
        switch value {
        case "black": return .black
        case "white": return .white
        case "red": return .red
        case "green": return .green
        case "blue": return .blue
        case "gray", "grey": return .gray
        case "yellow": return .yellow
        case "orange": return .orange
        case "purple": return .purple
        case "pink": return .systemPink
        default: return .black
        }
    }

    private static func hexColor(_ hex: String) -> UIColor? {
        let expanded: String
        if hex.count == 3 || hex.count == 4 {
            expanded = hex.map { "\($0)\($0)" }.joined()
        } else {
            expanded = hex
        }
        guard expanded.count == 6 || expanded.count == 8,
              let value = UInt64(expanded, radix: 16) else { return nil }
        let r: CGFloat
        let g: CGFloat
        let b: CGFloat
        let a: CGFloat
        if expanded.count == 8 {
            r = CGFloat((value >> 24) & 0xff) / 255
            g = CGFloat((value >> 16) & 0xff) / 255
            b = CGFloat((value >> 8) & 0xff) / 255
            a = CGFloat(value & 0xff) / 255
        } else {
            r = CGFloat((value >> 16) & 0xff) / 255
            g = CGFloat((value >> 8) & 0xff) / 255
            b = CGFloat(value & 0xff) / 255
            a = 1
        }
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }

    private static func rgbColor(_ raw: String) -> UIColor? {
        let values = SVGLengthParser.numberList(raw)
        guard values.count >= 3 else { return nil }
        let r = clampColorComponent(values[0])
        let g = clampColorComponent(values[1])
        let b = clampColorComponent(values[2])
        let a = values.count >= 4 ? max(0, min(values[3], 1)) : 1
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }

    private static func clampColorComponent(_ value: CGFloat) -> CGFloat {
        max(0, min(value / 255, 1))
    }
}

private final class SVGPathParser {
    private let tokens: [String]
    private var index = 0
    private var current = CGPoint.zero
    private var subpathStart = CGPoint.zero
    private var lastCubicControl: CGPoint?
    private var lastQuadraticControl: CGPoint?

    init(_ pathData: String) {
        tokens = SVGPathParser.tokenize(pathData)
    }

    func parse() -> UIBezierPath? {
        let path = UIBezierPath()
        var command: Character?
        while index < tokens.count {
            if let tokenCommand = commandCharacter(tokens[index]) {
                command = tokenCommand
                index += 1
            }
            guard let command else { return nil }
            consume(command, into: path)
        }
        return path.isEmpty ? nil : path
    }

    private func consume(_ command: Character, into path: UIBezierPath) {
        let relative = command.isLowercase
        switch command.uppercased() {
        case "M":
            guard let point = readPoint(relative: relative) else { return }
            path.move(to: point)
            current = point
            subpathStart = point
            clearControls()
            while let point = readPoint(relative: relative) {
                path.addLine(to: point)
                current = point
            }
        case "L":
            while let point = readPoint(relative: relative) {
                path.addLine(to: point)
                current = point
            }
            clearControls()
        case "H":
            while let x = readNumber() {
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: current)
            }
            clearControls()
        case "V":
            while let y = readNumber() {
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: current)
            }
            clearControls()
        case "C":
            while let c1 = readPoint(relative: relative),
                  let c2 = readPoint(relative: relative),
                  let end = readPoint(relative: relative) {
                path.addCurve(to: end, controlPoint1: c1, controlPoint2: c2)
                current = end
                lastCubicControl = c2
                lastQuadraticControl = nil
            }
        case "S":
            while let c2 = readPoint(relative: relative),
                  let end = readPoint(relative: relative) {
                let c1 = lastCubicControl.map { reflect($0, around: current) } ?? current
                path.addCurve(to: end, controlPoint1: c1, controlPoint2: c2)
                current = end
                lastCubicControl = c2
                lastQuadraticControl = nil
            }
        case "Q":
            while let control = readPoint(relative: relative),
                  let end = readPoint(relative: relative) {
                path.addQuadCurve(to: end, controlPoint: control)
                current = end
                lastQuadraticControl = control
                lastCubicControl = nil
            }
        case "T":
            while let end = readPoint(relative: relative) {
                let control = lastQuadraticControl.map { reflect($0, around: current) } ?? current
                path.addQuadCurve(to: end, controlPoint: control)
                current = end
                lastQuadraticControl = control
                lastCubicControl = nil
            }
        case "A":
            while skipArcPrefix(), let end = readPoint(relative: relative) {
                path.addLine(to: end)
                current = end
            }
            clearControls()
        case "Z":
            path.close()
            current = subpathStart
            clearControls()
        default:
            index = tokens.count
        }
    }

    private func readPoint(relative: Bool) -> CGPoint? {
        guard let x = readNumber(), let y = readNumber() else { return nil }
        return CGPoint(x: relative ? current.x + x : x, y: relative ? current.y + y : y)
    }

    private func readNumber() -> CGFloat? {
        guard index < tokens.count, commandCharacter(tokens[index]) == nil,
              let value = Double(tokens[index]) else { return nil }
        index += 1
        return CGFloat(value)
    }

    private func skipArcPrefix() -> Bool {
        let start = index
        for _ in 0..<5 {
            guard readNumber() != nil else {
                index = start
                return false
            }
        }
        return true
    }

    private func reflect(_ point: CGPoint, around center: CGPoint) -> CGPoint {
        CGPoint(x: center.x * 2 - point.x, y: center.y * 2 - point.y)
    }

    private func clearControls() {
        lastCubicControl = nil
        lastQuadraticControl = nil
    }

    private func commandCharacter(_ token: String) -> Character? {
        guard token.count == 1, let char = token.first,
              "AaCcHhLlMmQqSsTtVvZz".contains(char) else { return nil }
        return char
    }

    private static func tokenize(_ data: String) -> [String] {
        var tokens: [String] = []
        var number = ""
        var previous: Character?

        func flushNumber() {
            if !number.isEmpty {
                tokens.append(number)
                number = ""
            }
        }

        for char in data {
            if "AaCcHhLlMmQqSsTtVvZz".contains(char) {
                flushNumber()
                tokens.append(String(char))
            } else if char.isWhitespace || char == "," {
                flushNumber()
            } else {
                let startsSignedNumber = (char == "-" || char == "+") && !number.isEmpty && previous != "e" && previous != "E"
                if startsSignedNumber {
                    flushNumber()
                }
                number.append(char)
            }
            previous = char
        }
        flushNumber()
        return tokens
    }
}
#endif
