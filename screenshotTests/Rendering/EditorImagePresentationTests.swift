import AppKit
@testable import Screenshot_Bro
import Testing

/// The editor's window backing store is pinned to sRGB so CoreAnimation never colour-matches a
/// raster on the main thread at commit. These pin the conversion that keeps rasters in that space,
/// and — more importantly — that it never reaches the export path.
@MainActor
struct EditorImagePresentationTests {

    private func displayP3Image(width: Int, height: Int) throws -> CGImage {
        let space = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    @Test func displayReadyRetagsIntoTheWindowColorSpace() throws {
        let source = try displayP3Image(width: 16, height: 16)
        #expect(source.colorSpace?.name == CGColorSpace.displayP3)

        let converted = try #require(EditorImagePresentation.displayReady(source))
        #expect(converted.colorSpace?.name == CGColorSpace.sRGB)
        #expect(converted.width == source.width)
        #expect(converted.height == source.height)
    }

    /// CoreAnimation copies the image at commit unless the layout is already its own.
    @Test func displayReadyUsesCoreAnimationsLayerContentsLayout() throws {
        let source = try displayP3Image(width: 8, height: 8)
        let converted = try #require(EditorImagePresentation.displayReady(source))

        let alpha = CGImageAlphaInfo(rawValue: converted.bitmapInfo.rawValue & CGBitmapInfo.alphaInfoMask.rawValue)
        #expect(alpha == .premultipliedFirst)
        #expect(converted.bitmapInfo.contains(.byteOrder32Little))
        #expect(converted.bitsPerComponent == 8)
    }

    @Test func displayReadyLeavesItsSourceAlone() throws {
        let source = try displayP3Image(width: 8, height: 8)
        let converted = try #require(EditorImagePresentation.displayReady(source))

        #expect(converted !== source)
        #expect(source.colorSpace?.name == CGColorSpace.displayP3, "The source must not be retagged in place")
    }

    /// A conversion is not a retag: the numbers change so the *appearance* doesn't. Pure red in
    /// Display P3 is outside sRGB, so it clamps — but it must stay unmistakably red.
    @Test func displayReadyPreservesAppearance() throws {
        let source = try displayP3Image(width: 4, height: 4)
        let converted = try #require(EditorImagePresentation.displayReady(source))

        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try #require(CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(converted, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        #expect(pixel[0] > 200, "Red channel collapsed: \(pixel)")
        #expect(pixel[1] < 90, "Green leaked in: \(pixel)")
        #expect(pixel[2] < 90, "Blue leaked in: \(pixel)")
    }

    /// Export composites into DeviceRGB and encodes in DeviceRGB. The editor's pin must not reach
    /// it, or every shipped screenshot's bytes move.
    @Test func exportRasterizerStaysDeviceRGB() throws {
        let rep = try #require(RowRenderer.bitmapRep(width: 16, height: 16))
        #expect(rep.colorSpaceName == NSColorSpaceName.deviceRGB)
    }
}
