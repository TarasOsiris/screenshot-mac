import AppKit
import Foundation
@testable import Screenshot_Bro
import SwiftUI
import Testing

@MainActor
struct ShowcaseExportSettingsStoreTests {
    private let store = ShowcaseExportSettingsStore(
        directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("ShowcaseExportSettingsStoreTests-\(UUID().uuidString)", isDirectory: true)
    )

    private func tearDown() {
        try? FileManager.default.removeItem(at: store.directory)
    }

    private func save(_ config: ShowcaseExportConfig, backgroundImage: NSImage? = nil, changed: Bool = false) {
        store.save(config: config, backgroundImage: backgroundImage, backgroundImageChanged: changed)
        store.waitForPendingWrites()
    }

    @Test func nothingStoredLoadsDefaults() {
        defer { tearDown() }
        let restored = store.load()
        #expect(CodableColor(restored.config.bgColor) == CodableColor(ShowcaseExportConfig().bgColor))
        #expect(restored.config.aspectRatio == ShowcaseExportConfig().aspectRatio)
        #expect(restored.backgroundImage == nil)
    }

    @Test func everyFieldRoundTrips() {
        defer { tearDown() }
        var config = ShowcaseExportConfig()
        config.backgroundStyle = .image
        config.bgColor = Color(red: 0.2, green: 0.4, blue: 0.6)
        config.gradientConfig = GradientConfig(color1: Color(red: 1, green: 0, blue: 0), color2: Color(red: 0, green: 1, blue: 0), angle: 45, gradientType: .radial)
        config.backgroundImageConfig.svgContent = "<svg/>"
        config.backgroundImageConfig.fillMode = .tile
        config.spacingPercent = 5
        config.paddingPercent = 12
        config.cornerRadiusPercent = 4
        config.aspectRatio = ShowcaseAspectPreset.story.ratio
        config.maxOutputDimension = ShowcaseOutputSize.xlarge.maxDimension

        save(config)
        let loaded = store.load().config

        #expect(loaded.backgroundStyle == .image)
        #expect(CodableColor(loaded.bgColor) == CodableColor(config.bgColor))
        #expect(loaded.gradientConfig == config.gradientConfig)
        #expect(loaded.backgroundImageConfig == config.backgroundImageConfig)
        #expect(loaded.spacingPercent == 5)
        #expect(loaded.paddingPercent == 12)
        #expect(loaded.cornerRadiusPercent == 4)
        #expect(loaded.aspectRatio == ShowcaseAspectPreset.story.ratio)
        #expect(loaded.maxOutputDimension == ShowcaseOutputSize.xlarge.maxDimension)
    }

    /// A blob from another build may lack keys; each must fall back to its default.
    @Test func emptyBlobDecodesToDefaults() throws {
        let decoded = try JSONDecoder().decode(ShowcaseExportConfig.self, from: Data("{}".utf8))
        let defaults = ShowcaseExportConfig()
        #expect(decoded.backgroundStyle == defaults.backgroundStyle)
        #expect(decoded.paddingPercent == defaults.paddingPercent)
        #expect(decoded.maxOutputDimension == defaults.maxOutputDimension)
        #expect(decoded.backgroundImageConfig == defaults.backgroundImageConfig)
    }

    @Test func missingBackgroundFileDropsTheImageReference() {
        defer { tearDown() }
        var config = ShowcaseExportConfig()
        config.backgroundStyle = .image
        config.backgroundImageConfig.fileName = ShowcaseExportConfig.transientBackgroundKey
        save(config)

        let restored = store.load()
        #expect(restored.config.backgroundImageConfig.fileName == nil)
        #expect(restored.backgroundImage == nil)
    }

    @Test func backgroundImageRoundTripsAndIsRemovedWhenCleared() throws {
        defer { tearDown() }
        var config = ShowcaseExportConfig()
        config.backgroundStyle = .image
        config.backgroundImageConfig.fileName = ShowcaseExportConfig.transientBackgroundKey
        save(config, backgroundImage: try #require(makeImage(width: 12, height: 8)), changed: true)

        let restored = store.load()
        let loadedImage = try #require(restored.backgroundImage?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(loadedImage.width == 12)
        #expect(loadedImage.height == 8)
        #expect(restored.config.backgroundImageConfig.fileName == ShowcaseExportConfig.transientBackgroundKey)

        save(config, changed: true)
        #expect(!FileManager.default.fileExists(atPath: store.backgroundImageURL.path))
    }

    @Test func clearingRightAfterAPickLeavesNoBackgroundFile() throws {
        defer { tearDown() }
        var config = ShowcaseExportConfig()
        config.backgroundImageConfig.fileName = ShowcaseExportConfig.transientBackgroundKey
        store.save(config: config, backgroundImage: try #require(makeImage(width: 400, height: 400)), backgroundImageChanged: true)
        config.backgroundImageConfig.fileName = nil
        save(config, changed: true)

        #expect(!FileManager.default.fileExists(atPath: store.backgroundImageURL.path))
        #expect(store.load().config.backgroundImageConfig.fileName == nil)
    }

    private func makeImage(width: Int, height: Int) -> NSImage? {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let cgImage = context.makeImage() else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }
}
