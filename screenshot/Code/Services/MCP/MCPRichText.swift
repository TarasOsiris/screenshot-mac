#if os(macOS)
import AppKit
import Foundation
import SwiftUI

/// One styled span of a text shape, as agents read and write it.
struct MCPTextRun: Encodable, Equatable {
    let text: String
    let color: String
    /// `MCPRichText.systemFontName` for the system font.
    let fontName: String
    let fontSize: Double
    let fontWeight: Int
    let italic: Bool
    let underline: Bool?
    let strikethrough: Bool?
}

/// Translates a shape's Base64-RTF `richText` to and from `MCPTextRun`s.
enum MCPRichText {
    static let systemFontName = "system"

    /// The runs the canvas draws, or nil when every character renders in `shape`'s own style.
    static func runs(of shape: CanvasShapeModel) -> [MCPTextRun]? {
        let text = shape.text ?? ""
        guard let richText = shape.richText, let decoded = RichTextUtils.decode(richText), decoded.length > 0 else { return nil }
        var runs: [MCPTextRun] = []
        decoded.enumerateAttributes(in: NSRange(location: 0, length: decoded.length)) { attributes, range, _ in
            let span = (decoded.string as NSString).substring(with: range)
            let run = run(text: span, attributes: attributes)
            if let last = runs.last, last.withText("") == run.withText("") {
                runs[runs.count - 1] = last.withText(last.text + span)
            } else {
                runs.append(run)
            }
        }
        // A stale richText renders the new text in its first run's style (`retargetAttributedString`).
        if decoded.string != text, let first = runs.first {
            runs = [first.withText(text)]
        }
        if runs.count == 1, matchesShapeStyle(runs[0], shape) { return nil }
        return runs
    }

    /// Throws on any bad run before anything is mutated.
    static func validate(_ runs: [MCPArguments], availableFontFamilies: Set<String>) throws {
        guard !runs.isEmpty else {
            throw MCPToolError.invalidArgument("text_runs", "expected at least one run")
        }
        for run in runs {
            guard run.string("text") != nil else { throw MCPToolError.missingArgument("text_runs[].text") }
            _ = try run.color("color")
            if let fontName = run.string("font_name"), fontName != systemFontName, !availableFontFamilies.contains(fontName) {
                throw MCPToolError.invalidArgument("text_runs[].font_name", "font \(fontName) is not available")
            }
        }
        guard runs.contains(where: { !($0.string("text") ?? "").isEmpty }) else {
            throw MCPToolError.invalidArgument("text_runs", "the runs contain no text")
        }
    }

    /// Unset run fields inherit `shape`'s own style.
    static func encode(_ runs: [MCPArguments], onto shape: CanvasShapeModel, availableFontFamilies: Set<String>) throws -> (text: String, richText: String) {
        try validate(runs, availableFontFamilies: availableFontFamilies)
        let attributed = NSMutableAttributedString()
        for run in runs {
            var styled = shape
            if let fontName = run.string("font_name") {
                styled.fontName = fontName == systemFontName ? nil : fontName
            }
            let size = run.double("font_size").map { CGFloat($0) } ?? shape.fontSize ?? CanvasShapeModel.defaultFontSize
            let weight = run.int("font_weight") ?? shape.fontWeight ?? 700
            let font = TextFontResolver.resolvedFont(
                shape: styled, availableFontFamilies: availableFontFamilies, size: size,
                weight: CSSFontWeight(css: weight).platform, italic: run.bool("italic") ?? shape.italic ?? false
            )
            let color = try run.color("color") ?? shape.colorData
            var attributes = TextLayoutStyle.textAttributes(
                font: font, color: NSColor(color.color), alignment: shape.textAlign.nsTextAlignment,
                letterSpacing: shape.letterSpacing, lineHeightMultiple: shape.lineHeightMultiple,
                legacyLineSpacing: shape.lineSpacing
            )
            if run.bool("underline") == true { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if run.bool("strikethrough") == true { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            attributed.append(NSAttributedString(string: run.string("text") ?? "", attributes: attributes))
        }
        guard let richText = RichTextUtils.encode(attributed) else {
            throw MCPToolError.failed("Could not encode the formatted text")
        }
        return (attributed.string, richText)
    }

    private static func run(text: String, attributes: [NSAttributedString.Key: Any]) -> MCPTextRun {
        let font = attributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: CanvasShapeModel.defaultFontSize)
        let color = (attributes[.foregroundColor] as? NSColor).map { CodableColor(Color(nsColor: $0)).hexKey } ?? "#000000"
        let underline = (attributes[.underlineStyle] as? Int ?? 0) != 0
        let strikethrough = (attributes[.strikethroughStyle] as? Int ?? 0) != 0
        let family = font.familyName.flatMap { $0.hasPrefix(".") ? nil : $0 }
        return MCPTextRun(
            text: text,
            color: color,
            fontName: family ?? systemFontName,
            fontSize: Double(font.pointSize),
            fontWeight: CSSFontWeight(manager: NSFontManager.shared.weight(of: font)).css,
            italic: font.fontDescriptor.symbolicTraits.contains(.italic),
            underline: underline ? true : nil,
            strikethrough: strikethrough ? true : nil
        )
    }

    private static func matchesShapeStyle(_ run: MCPTextRun, _ shape: CanvasShapeModel) -> Bool {
        run.color == shape.colorData.hexKey
            && run.fontSize == Double(shape.fontSize ?? CanvasShapeModel.defaultFontSize)
            && CSSFontWeight(css: run.fontWeight) == CSSFontWeight(css: shape.fontWeight ?? 700)
            && run.italic == (shape.italic ?? false)
            && run.underline == nil && run.strikethrough == nil
    }
}

private extension MCPTextRun {
    func withText(_ text: String) -> MCPTextRun {
        MCPTextRun(
            text: text, color: color, fontName: fontName, fontSize: fontSize, fontWeight: fontWeight,
            italic: italic, underline: underline, strikethrough: strikethrough
        )
    }
}
#endif
