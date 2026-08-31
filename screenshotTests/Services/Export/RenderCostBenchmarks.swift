import AppKit
@testable import Screenshot_Bro
import SwiftUI
import Testing

/// Wall-clock probes for the export rasterizer, gated behind an env var. The `TEST_RUNNER_` prefix
/// is how Xcode forwards a variable into the test host, and is stripped on arrival:
///
///     TEST_RUNNER_SCREENSHOT_RENDER_BENCH=1 xcodebuild -scheme screenshot \
///       -destination 'platform=macOS' test -only-testing:screenshotTests/RenderCostBenchmarks
///
/// The `ImageRenderer` arm is a timing probe, **not** a drop-in: it doesn't apply the vertical flip
/// `cacheDisplay` does, which is the whole reason `ShadowModifier.compensatedOffset` exists.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["SCREENSHOT_RENDER_BENCH"] == "1"))
@MainActor
struct RenderCostBenchmarks {
    /// The size the export path actually rasterizes — a 6.5" iPhone screenshot, not a test-sized row.
    private static let templateWidth: CGFloat = 1242
    private static let templateHeight: CGFloat = 2688
    private static let deviceCount = 3
    private static let repetitions = 5

    private static let cases: [(label: String, radius: CGFloat?)] = [
        ("no shadow", nil),
        ("radius 40 (default)", 40),
        ("radius 150 (UI max)", 150),
    ]

    // MARK: - Fixtures

    private func makeRow(shadowRadius: CGFloat?) -> ScreenshotRow {
        var row = ScreenshotRow(
            templates: [ScreenshotTemplate()],
            templateWidth: Self.templateWidth,
            templateHeight: Self.templateHeight,
            bgColor: .white
        )
        row.shapes = (0..<Self.deviceCount).map { index in
            var device = CanvasShapeModel(
                type: .device,
                x: 320, y: 120 + CGFloat(index) * 820, width: 600, height: 760,
                color: .clear, deviceCategory: .iphone
            )
            if let shadowRadius {
                var shadow = ShadowConfig.preset(.medium)
                shadow.radius = shadowRadius
                device.shadow = shadow
            }
            return device
        }
        return row
    }

    /// `PlatformFonts.familyNameSet` rather than `NSFontManager.availableFontFamilies` so this
    /// matches the set `renderSingleTemplateImage` defaults to — otherwise the two arms below
    /// would be rendering different trees.
    private func shapesView(for row: ScreenshotRow) -> PresentationShapeLayerView {
        PresentationShapeLayerView(
            row: row,
            shapes: row.activeShapes,
            images: [:],
            displayScale: 1.0,
            defaultDeviceBodyColor: row.defaultDeviceBodyColor,
            availableFontFamilies: PlatformFonts.familyNameSet
        )
    }

    /// Mirrors `ViewRasterizer`'s iOS branch, minus its 8192px texture-limit downscale — equivalent
    /// at the sizes benched here, but not above them.
    private func renderViaImageRenderer(_ view: some View, width: CGFloat, height: CGFloat) -> NSImage? {
        let renderer = ImageRenderer(content:
            view
                .environment(\.isExportRendering, true)
                .environment(\.layoutDirection, .leftToRight)
                .frame(width: width, height: height, alignment: .topLeading)
                .clipped()
        )
        renderer.scale = 1
        renderer.isOpaque = false
        return renderer.nsImage
    }

    // MARK: - Measurement

    /// Median of `repetitions` runs after one warm-up, which absorbs SwiftUI/AppKit first-use cost.
    private func medianSeconds(_ body: () -> Void) -> Double {
        body()
        let samples = (0..<Self.repetitions).map { _ -> Double in
            let elapsed = ContinuousClock().measure { body() }
            return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        }
        return samples.sorted()[samples.count / 2]
    }

    /// Samples a grid; a render that drew nothing comes back all one colour.
    private static func hasNonUniformPixels(_ image: NSImage) -> Bool {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        var first: NSColor?
        for xStep in 0..<8 {
            for yStep in 0..<8 {
                guard let color = bitmap.colorAt(x: bitmap.pixelsWide * xStep / 8, y: bitmap.pixelsHigh * yStep / 8) else { continue }
                guard let first else {
                    first = color
                    continue
                }
                if color != first { return true }
            }
        }
        return false
    }

    // MARK: - Reporting

    /// `print` from an app-hosted test bundle doesn't reach `xcodebuild`'s captured output, so the
    /// table goes to stderr *and* to a file. The file is appended to, never truncated — xcodebuild
    /// may run more than one test host, so each process marks its own block.
    private static let reportURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("screenshot-render-bench.txt")
    private static var didWriteRunHeader = false

    private func report(_ label: String, _ seconds: Double) {
        var text = ""
        if !Self.didWriteRunHeader {
            Self.didWriteRunHeader = true
            text += "\n=== run \(Date()) pid \(ProcessInfo.processInfo.processIdentifier) ===\n"
        }
        text += String(
            format: "[render-bench] %@ %.1f ms\n",
            label.padding(toLength: 34, withPad: " ", startingAt: 0),
            seconds * 1000
        )

        let data = Data(text.utf8)
        FileHandle.standardError.write(data)
        if let handle = try? FileHandle(forWritingTo: Self.reportURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: Self.reportURL)
        }
    }

    // MARK: - How much of a template render is the shadow?

    @Test func shadowShareOfTemplateRender() {
        for (label, radius) in Self.cases {
            let row = makeRow(shadowRadius: radius)
            let probe = RowRenderer.renderSingleTemplateImage(index: 0, row: row)
            #expect(probe.size.width == Self.templateWidth)
            #expect(probe.size.height == Self.templateHeight)

            report("templateImage · \(label)", medianSeconds {
                _ = RowRenderer.renderSingleTemplateImage(index: 0, row: row)
            })
        }
    }

    // MARK: - Is ImageRenderer cheaper than cacheDisplay for the same tree?

    @Test func rasterizerComparisonOnTheShapeLayer() {
        let width = Self.templateWidth
        let height = Self.templateHeight

        for (label, radius) in Self.cases.dropLast() {
            let view = shapesView(for: makeRow(shadowRadius: radius))

            report("cacheDisplay · \(label)", medianSeconds {
                _ = RowRenderer.renderViewToImage(view, width: width, height: height, label: "bench")
            })

            // A blank or nil render is very fast and would read as a huge win — prove it drew the
            // shapes before the number below means anything.
            guard let probe = renderViaImageRenderer(view, width: width, height: height),
                  probe.size.width == width else {
                Issue.record("ImageRenderer produced no image at full width for \(label)")
                continue
            }
            #expect(Self.hasNonUniformPixels(probe), "ImageRenderer produced a uniform (blank) image")

            report("ImageRenderer · \(label)", medianSeconds {
                _ = renderViaImageRenderer(view, width: width, height: height)
            })
        }
    }
}
