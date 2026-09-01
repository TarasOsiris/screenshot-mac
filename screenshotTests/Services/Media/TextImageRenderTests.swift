#if os(macOS)
import AppKit
@testable import Screenshot_Bro
import Testing

/// `TextLayoutStyle.renderImage` is the only text path the canvas has left — the editor stopped
/// hosting a live `TextLayoutNSView` per shape — so a blank or shifted raster would silently
/// break every text shape on screen *and* in export.
@Suite(.serialized)
@MainActor
struct TextImageRenderTests {

    private static let size = CGSize(width: 240, height: 80)
    private static let font = NSFont.systemFont(ofSize: 32, weight: .bold)

    private func render(scale: CGFloat? = nil, text: String = "Hello", color: NSColor = .black) -> NSImage? {
        TextLayoutStyle.renderImage(
            size: Self.size,
            text: text,
            font: Self.font,
            color: color,
            alignment: .center,
            verticalAlignment: .center,
            uppercase: false,
            letterSpacing: nil,
            lineHeightMultiple: nil,
            legacyLineSpacing: nil,
            richTextData: nil,
            renderScale: scale ?? TextLayoutStyle.defaultTextRenderScale
        )
    }

    /// Fraction of sampled pixels carrying any alpha. Catches the failure that matters most: a
    /// raster that comes back the right size but entirely empty.
    private func coverage(_ image: NSImage) -> Double {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return 0 }
        let side = 64
        var alpha = [UInt8](repeating: 0, count: side * side)
        guard let context = CGContext(
            data: &alpha, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
        ) else { return 0 }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        return Double(alpha.count { $0 > 0 }) / Double(alpha.count)
    }

    @Test func rendersGlyphsAtTheDefaultScale() throws {
        let image = try #require(render())
        #expect(image.size == Self.size)
        #expect(coverage(image) > 0.01)
    }

    /// The guard on export parity. `renderImage` used to rasterize through
    /// `bitmapImageRepForCachingDisplay` + `cacheDisplay`, which silently picked the main screen's
    /// backing scale and the Generic RGB space; the explicit `NSBitmapImageRep` that replaced it
    /// has to reproduce both exactly, or every exported glyph moves.
    @Test func defaultScaleMatchesTheImplicitCachingDisplayPathPixelForPixel() throws {
        let view = TextLayoutNSView(frame: NSRect(origin: .zero, size: Self.size))
        view.configure(
            text: "Hello Parity", font: Self.font, color: .systemBlue, alignment: .center,
            verticalAlignment: .center, uppercase: false, letterSpacing: nil,
            lineHeightMultiple: nil, legacyLineSpacing: nil, richTextData: nil
        )
        view.layoutSubtreeIfNeeded()
        let reference = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: reference)

        let rendered = try #require(render(text: "Hello Parity", color: .systemBlue))
        let rep = try #require(rendered.representations.first as? NSBitmapImageRep)

        #expect(rep.pixelsWide == reference.pixelsWide)
        #expect(rep.pixelsHigh == reference.pixelsHigh)
        #expect(rep.colorSpace == reference.colorSpace)

        var maxDelta: CGFloat = 0
        for y in stride(from: 0, to: reference.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: reference.pixelsWide, by: 2) {
                guard let a = reference.colorAt(x: x, y: y), let b = rep.colorAt(x: x, y: y) else { continue }
                maxDelta = max(maxDelta, [
                    abs(a.redComponent - b.redComponent), abs(a.greenComponent - b.greenComponent),
                    abs(a.blueComponent - b.blueComponent), abs(a.alphaComponent - b.alphaComponent)
                ].max() ?? 0)
            }
        }
        #expect(maxDelta == 0)
    }

    @Test func supersampledRenderKeepsPointSizeAndStillDrawsGlyphs() throws {
        let baseline = try #require(render())
        let supersampled = try #require(render(scale: TextLayoutStyle.maxTextRenderScale))

        // Point size is what every caller frames against; only the backing pixels grow.
        #expect(supersampled.size == Self.size)
        let rep = try #require(supersampled.representations.first as? NSBitmapImageRep)
        #expect(rep.pixelsWide == Int(Self.size.width * TextLayoutStyle.maxTextRenderScale))
        #expect(rep.pixelsHigh == Int(Self.size.height * TextLayoutStyle.maxTextRenderScale))

        // Same glyphs, so the inked fraction should match closely — a wrong CTM would shift or
        // rescale the text and blow this apart.
        #expect(abs(coverage(supersampled) - coverage(baseline)) < 0.05)
    }

    @Test func emptySizeRendersNothing() {
        #expect(TextLayoutStyle.renderImage(
            size: .zero, text: "Hello", font: Self.font, color: .black,
            alignment: .center, verticalAlignment: .center, uppercase: false, letterSpacing: nil,
            lineHeightMultiple: nil, legacyLineSpacing: nil
        ) == nil)
    }

    @Test func nonFiniteSizeRendersNothing() {
        #expect(TextLayoutStyle.renderImage(
            size: CGSize(width: .infinity, height: Self.size.height), text: "Hello",
            font: Self.font, color: .black, alignment: .center,
            verticalAlignment: .center, uppercase: false, letterSpacing: nil,
            lineHeightMultiple: nil, legacyLineSpacing: nil
        ) == nil)
    }

    @Test func identicalRenderReusesTheCachedImage() throws {
        let first = try #require(render(text: "Cache me"))
        let second = try #require(render(text: "Cache me"))
        #expect(first === second)
    }

    /// Continuous scales would miss the cache on every zoom step the bucket exists to survive.
    /// The floor is 1, not the export default — an editor raster that is scaled down on screen must
    /// be allowed to render smaller, or it burns pixels and cache bytes it can never show.
    @Test func renderScaleQuantizesToIntegerBucketsFromOne() {
        #expect(TextLayoutStyle.quantizedTextRenderScale(0.19) == 1)
        #expect(TextLayoutStyle.quantizedTextRenderScale(1) == 1)
        #expect(TextLayoutStyle.quantizedTextRenderScale(1.01) == 2)
        #expect(TextLayoutStyle.quantizedTextRenderScale(2) == 2)
        #expect(TextLayoutStyle.quantizedTextRenderScale(99) == TextLayoutStyle.maxTextRenderScale)
        #expect(TextLayoutStyle.quantizedTextRenderScale(.nan) == 1)
    }

    /// Export and preview must keep asking for the default, whatever the editor does.
    @Test func exportPathKeepsTheImplicitDefaultScale() {
        #expect(TextLayoutStyle.defaultTextRenderScale == 2)
        let image = TextLayoutStyle.renderImage(
            size: Self.size, text: "Hello", font: Self.font, color: .black, alignment: .center,
            verticalAlignment: .center, uppercase: false, letterSpacing: nil,
            lineHeightMultiple: nil, legacyLineSpacing: nil
        )
        let rep = image?.representations.first as? NSBitmapImageRep
        #expect(rep?.pixelsWide == Int(Self.size.width * TextLayoutStyle.defaultTextRenderScale))
    }

    @Test func cacheKeySeparatesEveryStyledInput() {
        func key(
            scale: CGFloat = 1, text: String = "Hello", font: NSFont = TextImageRenderTests.font,
            color: NSColor = .black, alignment: NSTextAlignment = .center,
            verticalAlignment: TextVerticalAlign = .center, uppercase: Bool = false,
            letterSpacing: CGFloat? = nil, lineHeightMultiple: CGFloat? = nil,
            legacyLineSpacing: CGFloat? = nil, richTextData: String? = nil,
            size: CGSize = TextImageRenderTests.size
        ) -> String {
            TextLayoutStyle.textImageCacheKey(
                size: size, scale: scale, text: text, font: font, color: color, alignment: alignment,
                verticalAlignment: verticalAlignment, uppercase: uppercase, letterSpacing: letterSpacing,
                lineHeightMultiple: lineHeightMultiple, legacyLineSpacing: legacyLineSpacing,
                richTextData: richTextData
            )
        }
        let base = key()
        #expect(key() == base)
        #expect(key(scale: 2) != base)
        #expect(key(text: "Hellp") != base)
        #expect(key(font: .systemFont(ofSize: 33, weight: .bold)) != base)
        #expect(key(color: .red) != base)
        #expect(key(alignment: .left) != base)
        #expect(key(verticalAlignment: .top) != base)
        #expect(key(uppercase: true) != base)
        #expect(key(letterSpacing: 2) != base)
        #expect(key(lineHeightMultiple: 1.5) != base)
        #expect(key(legacyLineSpacing: 4) != base)
        #expect(key(richTextData: "abc") != base)
        #expect(key(size: CGSize(width: 241, height: 80)) != base)
        #expect(key(size: CGSize(width: 240.1, height: 80)) != key(size: CGSize(width: 240.4, height: 80)))
        #expect(
            key(color: NSColor(srgbRed: 0.5001, green: 0.5, blue: 0.5, alpha: 1))
                != key(color: NSColor(srgbRed: 0.5004, green: 0.5, blue: 0.5, alpha: 1))
        )
    }

    /// Two weights of one family can share a PostScript name once a variable font is resolved to an
    /// instance, so the descriptor's weight trait has to be in the key on its own.
    @Test func cacheKeySeparatesWeightsOfOneFamily() {
        func key(_ weight: NSFont.Weight) -> String {
            TextLayoutStyle.textImageCacheKey(
                size: Self.size, scale: 1, text: "Hello",
                font: .systemFont(ofSize: 32, weight: weight), color: .black,
                alignment: .center, verticalAlignment: .center, uppercase: false,
                letterSpacing: nil, lineHeightMultiple: nil, legacyLineSpacing: nil, richTextData: nil
            )
        }
        #expect(key(.regular) != key(.black))
    }
}
#endif
