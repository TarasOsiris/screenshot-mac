import AppKit
import CoreGraphics
@testable import Screenshot_Bro
import SwiftUI
import Testing

extension ExportServiceTests {
    @Test func deviceAspectRatioIsNormalizedInExport() throws {
        let tw: CGFloat = 400
        let th: CGFloat = 800
        var row = makeTestRow(width: tw, height: th, bgColor: Self.testBlue)
        // iPhone aspect ~0.489. Square shape → normalization narrows it.
        row.shapes = [CanvasShapeModel(
            type: .device, x: 50, y: 100, width: 300, height: 300,
            color: .clear, deviceCategory: .iphone
        )]
        let bitmap = try renderTemplateBitmap(index: 0, row: row)

        // After normalization the device is narrower; original right edge (350) is background
        try expectDominant(bitmap, at: (340, 250), channel: .b, label: "right of normalized device")
    }

    /// Regression: a frameless generic Android device flexes its box to the dropped screenshot's
    /// aspect (`adaptToImageAspectRatio`), unlike a real iPhone frame. The export path must NOT
    /// re-normalize it back to the category's fixed aspect — that shrank the device (gap at the
    /// row edge), so the exported PNG no longer matched the editor canvas. Counterpart to
    /// `deviceAspectRatioIsNormalizedInExport` (which asserts the iPhone IS normalized).
    @Test func flexedAndroidDeviceKeepsImageAspectInExport() throws {
        let tw: CGFloat = 400, th: CGFloat = 800
        var row = makeTestRow(width: tw, height: th, bgColor: Self.testBlue)
        // Square box vs Android intrinsic aspect (~0.48): normalization would narrow the device to
        // ~144pt wide (centered, right edge ~272), exposing blue background where the device should
        // still be. A green screenshot fills the device screen so it reads distinctly from the bg.
        row.shapes = [CanvasShapeModel(
            type: .device, x: 50, y: 100, width: 300, height: 300,
            color: .clear, deviceCategory: .androidPhone,
            screenshotFileName: "screen"
        )]
        let images = ["screen": makeSolidImage(NSColor(Self.testGreen), width: 600, height: 600)]

        let exportBmp = try renderSingleTemplateBitmap(index: 0, row: row, screenshotImages: images)
        let editorBmp = try renderEditorBitmap(index: 0, row: row, screenshotImages: images)

        // (320, 250) is inside the box (x 50..350) but right of the would-be-normalized device
        // (right edge ~272). The flexed device must fill it — green screen — in BOTH paths. Before
        // the fix, export normalization left this point as blue background while the editor stayed
        // green; afterwards both are green.
        try expectDominant(exportBmp, at: (320, 250), channel: .g,
                           label: "export: flexed Android device must fill its box (not normalized)")
        try expectDominant(editorBmp, at: (320, 250), channel: .g,
                           label: "editor: Android device fills its box (control)")
    }

    @Test func modelBackedDeviceFrameRendersVisibleContentInExport() throws {
        var row = makeTestRow(width: 500, height: 900, bgColor: .white)
        row.shapes = [CanvasShapeModel(
            type: .device,
            x: 90,
            y: 80,
            width: 320,
            height: 720,
            color: .clear,
            deviceCategory: .iphone,
            deviceFrameId: "iphone16model-default-portrait",
            screenshotFileName: "model-screen"
        )]

        let bitmap = try renderTemplateBitmap(
            index: 0,
            row: row,
            screenshotImages: ["model-screen": makeTestImage(width: 1206, height: 2622)]
        )

        try expectHasNonWhitePixel(bitmap, label: "Model-backed device frame should render visible pixels")
    }

    @Test func iphone17ProMaxModelBackedDeviceFrameRendersVisibleContentInExport() throws {
        var row = makeTestRow(width: 500, height: 900, bgColor: .white)
        row.shapes = [CanvasShapeModel(
            type: .device,
            x: 90,
            y: 80,
            width: 320,
            height: 720,
            color: .clear,
            deviceCategory: .iphone,
            deviceFrameId: "iphone17promaxmodel-default-portrait",
            screenshotFileName: "model-screen"
        )]

        let bitmap = try renderTemplateBitmap(
            index: 0,
            row: row,
            screenshotImages: ["model-screen": makeTestImage(width: 1320, height: 2868)]
        )

        try expectHasNonWhitePixel(bitmap, label: "iPhone 17 Pro Max 3D frame should render visible pixels")
        try expectHasDominantPixel(
            bitmap,
            region: CGRect(x: 170, y: 210, width: 160, height: 380),
            channel: .b,
            label: "iPhone 17 Pro Max 3D frame should show the screenshot on its screen"
        )
    }

    @Test func modelBackedDeviceRotationChangesExportOutput() throws {
        let screenshotImages = ["model-screen": makeTestImage(width: 1206, height: 2622)]
        var leftRow = makeTestRow(width: 500, height: 900, bgColor: .white)
        leftRow.shapes = [CanvasShapeModel(
            type: .device,
            x: 90,
            y: 80,
            width: 320,
            height: 720,
            color: .clear,
            deviceCategory: .iphone,
            deviceFrameId: "iphone16model-default-portrait",
            screenshotFileName: "model-screen",
            deviceYaw: -30
        )]

        var rightRow = leftRow
        rightRow.shapes[0].deviceYaw = 30

        let leftBitmap = try renderTemplateBitmap(index: 0, row: leftRow, screenshotImages: screenshotImages)
        let rightBitmap = try renderTemplateBitmap(index: 0, row: rightRow, screenshotImages: screenshotImages)

        try expectBitmapsDiffer(leftBitmap, rightBitmap, label: "Changing model yaw should change exported pixels")
    }

    @Test func modelBackedDeviceFramePreservesBackgroundOutsidePhoneInExport() throws {
        var row = makeTestRow(width: 500, height: 900, bgColor: Self.testBlue)
        row.shapes = [CanvasShapeModel(
            type: .device,
            x: 90,
            y: 80,
            width: 320,
            height: 720,
            color: .clear,
            deviceCategory: .iphone,
            deviceFrameId: "iphone16model-default-portrait",
            screenshotFileName: "model-screen"
        )]

        let bitmap = try renderTemplateBitmap(
            index: 0,
            row: row,
            screenshotImages: ["model-screen": makeTestImage(width: 1206, height: 2622)]
        )

        try expectDominant(bitmap, at: (100, 100), channel: .b, label: "background around 3D phone should stay blue")
    }

    @Test func modelBackedDeviceExportMatchesEditorBrightness() throws {
        let screenshotImages = ["model-screen": makeTestImage(width: 1206, height: 2622)]
        var row = makeTestRow(width: 500, height: 900, bgColor: .white)
        row.shapes = [CanvasShapeModel(
            type: .device,
            x: 90,
            y: 80,
            width: 320,
            height: 720,
            color: .clear,
            deviceCategory: .iphone,
            deviceFrameId: "iphone16model-default-portrait",
            screenshotFileName: "model-screen"
        )]

        let exportBitmap = try renderTemplateBitmap(index: 0, row: row, screenshotImages: screenshotImages)
        let editorBitmap = try renderEditorBitmap(index: 0, row: row, screenshotImages: screenshotImages)
        let exportBrightness = try averageBrightnessOfVisibleContent(exportBitmap)
        let editorBrightness = try averageBrightnessOfVisibleContent(editorBitmap)
        let delta = abs(exportBrightness - editorBrightness)

        #expect(delta < 0.08, "Model-backed device brightness should match editor, delta=\(delta)")
    }

    @Test func modelBackedDeviceLargeExportUsesExpectedBounds() throws {
        let screenshotImages = ["model-screen": makeTestImage(width: 1206, height: 2622)]
        var row = makeTestRow(width: 1290, height: 2796, bgColor: .white)
        row.shapes = [CanvasShapeModel(
            type: .device,
            x: 165,
            y: 180,
            width: 960,
            height: 2160,
            color: .clear,
            deviceCategory: .iphone,
            deviceFrameId: "iphone16model-default-portrait",
            screenshotFileName: "model-screen",
            deviceYaw: 18
        )]

        let bitmap = try renderTemplateBitmap(index: 0, row: row, screenshotImages: screenshotImages)
        try expectHasNonWhitePixel(bitmap, region: CGRect(x: 260, y: 1120, width: 120, height: 400), label: "left half of large 3D device")
        try expectHasNonWhitePixel(bitmap, region: CGRect(x: 910, y: 1120, width: 120, height: 400), label: "right half of large 3D device")
        try expectWhitePixel(bitmap, at: (80, 240), label: "background outside large 3D device")
    }
}
