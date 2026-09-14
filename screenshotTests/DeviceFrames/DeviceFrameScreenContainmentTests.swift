import AppKit
@testable import Screenshot_Bro
import SwiftUI
import Testing

/// Renders every 2D device frame over a green canvas, once with a transparent screenshot and once
/// with a magenta one. The first pass maps the canvas around the device (green reachable from the
/// image border); the second must put no magenta there — the screenshot sticking out past the
/// bezel — and no green inside the screen that the first pass found enclosed — the canvas showing
/// through a screen corner.
@MainActor
struct DeviceFrameScreenContainmentTests {

    enum Subject: CustomTestStringConvertible, Sendable {
        case image(frameId: String)
        case programmatic(DeviceCategory)

        var testDescription: String {
            switch self {
            case .image(let frameId): frameId
            case .programmatic(let category): "programmatic-\(category.rawValue)"
            }
        }
    }

    /// Colors share their group's screen geometry, so one color per group covers every aperture.
    nonisolated static let subjects: [Subject] =
        DeviceFrameCatalog.groups.compactMap(\.colorGroups.first).flatMap(\.frames)
            .filter { $0.imageName != nil }
            .map { .image(frameId: $0.id) }
        + DeviceCategory.allCases.filter { $0 != .invisible }.map { .programmatic($0) }

    /// Export draws at model scale; the editor draws a phone a few hundred points tall, where the
    /// fixed 1pt screenshot bleed is proportionally largest against the bezel.
    @Test(arguments: subjects, [1400.0, 260.0])
    func screenshotStaysInsideTheBezel(subject: Subject, longEdge: CGFloat) throws {
        let frame: DeviceFrame?
        let category: DeviceCategory
        let base: (width: CGFloat, height: CGFloat)
        switch subject {
        case .image(let frameId):
            let imageFrame = try #require(DeviceFrameCatalog.frame(for: frameId))
            (frame, category, base) = (imageFrame, imageFrame.fallbackCategory, imageFrame.baseDimensions)
        case .programmatic(let fallback):
            (frame, category, base) = (nil, fallback, fallback.baseDimensions)
        }
        let scale = longEdge / max(base.width, base.height)
        let size = CGSize(width: (base.width * scale).rounded(), height: (base.height * scale).rounded())

        let outline = try render(frame: frame, category: category, size: size, screenshot: Self.transparentScreenshot)
        let filled = try render(frame: frame, category: category, size: size, screenshot: Self.magentaScreenshot)
        let outside = canvasReachableFromBorder(outline)

        var stickingOut = 0
        for index in outside.indices where outside[index] && filled.isMagenta(index) {
            stickingOut += 1
        }

        // Only the screen counts for show-through: watch bands have real holes.
        let screen = frame?.spec.screenRect(in: size) ?? CGRect(origin: .zero, size: size)
        var showingThrough = 0
        for y in Int(screen.minY.rounded())..<Int(screen.maxY.rounded()) {
            for x in Int(screen.minX.rounded())..<Int(screen.maxX.rounded()) {
                let index = y * filled.width + x
                if !outside[index] && filled.isCanvas(index) { showingThrough += 1 }
            }
        }

        #expect(stickingOut == 0, "\(subject.testDescription) @\(Int(longEdge)): \(stickingOut) screenshot pixels outside the bezel")
        #expect(showingThrough == 0, "\(subject.testDescription) @\(Int(longEdge)): \(showingThrough) canvas pixels inside the screen")
    }

    // MARK: - Rendering

    private static let magentaScreenshot = makeSolidImage(NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1), width: 8, height: 8)
    private static let transparentScreenshot = makeSolidImage(.clear, width: 8, height: 8)

    private func render(frame: DeviceFrame?, category: DeviceCategory, size: CGSize, screenshot: NSImage) throws -> Pixels {
        let view = ZStack(alignment: .topLeading) {
            Color(red: 0, green: 1, blue: 0)
            DeviceFrameView(
                category: category, bodyColor: .black,
                width: size.width, height: size.height,
                screenshotImage: screenshot, deviceFrameId: frame?.id
            )
        }
        .frame(width: size.width, height: size.height)
        let image = RowRenderer.renderViewToImage(view, width: size.width, height: size.height, label: "containment")
        let bitmap = try #require(image.representations.first as? NSBitmapImageRep)
        try #require(bitmap.pixelsWide == Int(size.width) && bitmap.pixelsHigh == Int(size.height))
        return try Pixels(bitmap)
    }

    private func canvasReachableFromBorder(_ pixels: Pixels) -> [Bool] {
        let width = pixels.width, height = pixels.height
        var reached = [Bool](repeating: false, count: width * height)
        var stack: [Int] = []
        stack.reserveCapacity(2 * (width + height))
        for x in 0..<width { stack += [x, (height - 1) * width + x] }
        for y in 0..<height { stack += [y * width, y * width + width - 1] }
        while let index = stack.popLast() {
            guard !reached[index], pixels.isCanvas(index) else { continue }
            reached[index] = true
            let x = index % width
            if x > 0 { stack.append(index - 1) }
            if x < width - 1 { stack.append(index + 1) }
            if index >= width { stack.append(index - width) }
            if index < (height - 1) * width { stack.append(index + width) }
        }
        return reached
    }

    /// Reads the render's own bitmap in place; classifying on demand beats building arrays up front.
    struct Pixels {
        let width: Int
        let height: Int
        private let bitmap: NSBitmapImageRep
        private let data: UnsafeMutablePointer<UInt8>
        private let bytesPerPixel: Int

        init(_ bitmap: NSBitmapImageRep) throws {
            data = try #require(bitmap.bitmapData)
            try #require(bitmap.bitsPerSample == 8 && !bitmap.isPlanar && !bitmap.bitmapFormat.contains(.alphaFirst))
            self.bitmap = bitmap
            width = bitmap.pixelsWide
            height = bitmap.pixelsHigh
            bytesPerPixel = bitmap.bitsPerPixel / 8
        }

        func isCanvas(_ index: Int) -> Bool {
            let (red, green, blue) = rgb(index)
            return green - max(red, blue) > 128
        }

        func isMagenta(_ index: Int) -> Bool {
            let (red, green, blue) = rgb(index)
            return min(red, blue) - green > 128
        }

        private func rgb(_ index: Int) -> (Int, Int, Int) {
            let offset = (index / width) * bitmap.bytesPerRow + (index % width) * bytesPerPixel
            return (Int(data[offset]), Int(data[offset + 1]), Int(data[offset + 2]))
        }
    }
}
