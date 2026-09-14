import CoreGraphics
@testable import Screenshot_Bro
import SwiftUI
import Testing

struct DeviceFrameCatalogTests {

    @Test func groupsMirrorDefinitionEntries() {
        let entries = DeviceFrameCatalogDefinitions.entries
        let groups = DeviceFrameCatalog.groups

        #expect(groups.count == entries.count)
        #expect(groups.map(\.id) == entries.map(\.groupId))
        #expect(groups.map(\.name) == entries.map(\.modelName))
        #expect(groups.map(\.family) == entries.map(\.family))
    }

    @Test func sectionsFollowFamilyOrder() {
        let expectedFamilies = DeviceFrameFamily.allCases.filter { family in
            !family.genericCategories.isEmpty || DeviceFrameCatalog.groups.contains(where: { $0.family == family })
        }

        #expect(DeviceFrameCatalog.sections.map(\.family) == expectedFamilies)
        #expect(DeviceFrameCatalog.sections.first(where: { $0.family == .other })?.categories == [.invisible])
    }

    /// The picker lists the newest iPhones first, but iPhone 17 is still the flagged default.
    @Test func firstPortraitFrameIdPrefersFlaggedDefaultThenFirstCatalogMatch() {
        #expect(DeviceFrameCatalog.firstPortraitFrameId(for: .iphone) == "iphone17-black-portrait")
        #expect(DeviceFrameCatalog.firstPortraitFrameId(for: .ipadPro11) == "ipadpro11-silver-portrait")
        #expect(DeviceFrameCatalog.firstPortraitFrameId(for: .macbook) == nil)
    }

    @Test func firstFrameResolvesLandscapePerCategory() {
        #expect(DeviceFrameCatalog.firstFrame(for: .ipadPro11, isLandscape: true)?.id == "ipadpro11-silver-landscape")
        #expect(DeviceFrameCatalog.firstFrame(for: .ipadPro13, isLandscape: true)?.id == "ipadpro13-silver-landscape")
        #expect(DeviceFrameCatalog.firstFrame(for: .iphone, isLandscape: true)?.id == "iphone17-black-landscape")
        // Macs are landscapeOnly, so they have no portrait frame at all.
        #expect(DeviceFrameCatalog.firstFrame(for: .macbook, isLandscape: false) == nil)
        #expect(DeviceFrameCatalog.firstFrame(for: .macbook, isLandscape: true) != nil)
        // Android categories have no catalog frames in either orientation.
        #expect(DeviceFrameCatalog.firstFrame(for: .androidTablet, isLandscape: true) == nil)
    }

    @Test func preferredFramePreservesColorAndOrientation() {
        let currentFrameId = "iphone17pro-deepblue-landscape"
        let preferredFrame = DeviceFrameCatalog.preferredFrame(
            forGroupId: "iphone17pro",
            matching: currentFrameId
        )

        #expect(preferredFrame?.id == currentFrameId)
    }

    @Test func variantSwitchesOrientationWithinSameColorGroup() {
        let toggled = DeviceFrameCatalog.variant(
            forFrameId: "iphone17-black-portrait",
            isLandscape: true
        )

        #expect(toggled?.id == "iphone17-black-landscape")
    }

    @Test func suggestedPresetFlipsForLandscapeFrames() {
        let preset = DeviceFrameCatalog.suggestedSizePreset(
            forFrameId: "iphone17-black-landscape"
        )

        #expect(preset == "2622x1206")
    }

    @Test func appleWatchExposesBothOrientationsViaRotation() {
        let portraitId = "applewatchultra3-blackoceanbandblack-portrait"
        let landscape = DeviceFrameCatalog.variant(forFrameId: portraitId, isLandscape: true)

        #expect(DeviceFrameCatalog.frame(for: portraitId) != nil)
        #expect(landscape?.isLandscape == true)
        #expect(landscape?.spec.frameWidth == 960)
        #expect(landscape?.spec.frameHeight == 600)
        // The watch art was drawn for a clockwise turn; the iPhone/iPad art was not.
        #expect(landscape?.landscapeRotationDegrees == 90)
    }

    /// The image-backed phone/tablet groups ship no landscape PNG — landscape reuses the portrait
    /// asset turned counter-clockwise, which is the direction that art was rendered in.
    @Test(arguments: [
        "iphone17-black", "iphone17pro-silver", "iphone17promax-deepblue",
        "iphoneair-skyblue", "ipadpro11-silver", "ipadpro13-spacegray",
        "iphone18pro-glacier", "iphone18promax-burgundy", "iphoneduoclosed-nightsky",
    ])
    func landscapeFramesReusePortraitArtRotatedCounterClockwise(colorSlug: String) throws {
        let portrait = try #require(DeviceFrameCatalog.frame(for: "\(colorSlug)-portrait"))
        let landscape = try #require(DeviceFrameCatalog.variant(forFrameId: portrait.id, isLandscape: true))

        #expect(landscape.landscapeRotationDegrees == 270)
        #expect(landscape.imageName == portrait.imageName)
        #expect(landscape.spec.frameWidth == portrait.spec.frameHeight)
        #expect(landscape.spec.frameHeight == portrait.spec.frameWidth)
        #expect(portrait.landscapeRotationDegrees == nil)
    }

    /// The Duo's inner-screen landscape art was rendered clockwise, unlike its outer screen.
    @Test func iphoneDuoInnerLandscapeReusesPortraitArtRotatedClockwise() throws {
        let portrait = try #require(DeviceFrameCatalog.frame(for: "iphoneduo-starwhite-portrait"))
        let landscape = try #require(DeviceFrameCatalog.variant(forFrameId: portrait.id, isLandscape: true))

        #expect(landscape.landscapeRotationDegrees == 90)
        #expect(landscape.imageName == portrait.imageName)
    }

    @Test func iphoneDuoOpenBackViewIsLandscapeOnly() throws {
        let frame = try #require(DeviceFrameCatalog.frame(for: "iphoneduoopen-nightsky-landscape"))

        #expect(frame.landscapeRotationDegrees == nil)
        #expect(frame.imageName == "DeviceFrames/iphoneduoopen-nightsky-landscape")
        #expect(DeviceFrameCatalog.frame(for: "iphoneduoopen-nightsky-portrait") == nil)
    }

    /// Renders each new bezel over green with a magenta screenshot. Green the bezel fully encloses
    /// means the clip radius is too large and the canvas shows through a screen corner; green
    /// reachable from the image border is just the canvas around the device.
    @Test(arguments: ["iphone18pro", "iphone18promax", "iphoneduo", "iphoneduoclosed", "iphoneduoopen"])
    func screenshotFillsTheWholeApertureWithoutGaps(groupId: String) throws {
        let group = try #require(DeviceFrameCatalog.groups.first { $0.id == groupId })
        let frames = try #require(group.colorGroups.first).frames
        let screenshot = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
            NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1).setFill()
            rect.fill()
            return true
        }

        for frame in frames {
            let width = (frame.spec.frameWidth / 2).rounded()
            let height = (frame.spec.frameHeight / 2).rounded()
            let view = ZStack(alignment: .topLeading) {
                Color(red: 0, green: 1, blue: 0)
                DeviceFrameImageView(frame: frame, width: width, height: height, screenshotImage: screenshot)
            }
            .frame(width: width, height: height)
            let image = RowRenderer.renderViewToImage(view, width: width, height: height, label: "aperture")
            let png = try #require(ExportService.opaquePNGData(from: image))
            let bitmap = try #require(NSBitmapImageRep(data: png))
            let gaps = try enclosedCanvasPixelCount(bitmap)
            #expect(gaps == 0, "\(frame.id): \(gaps) canvas pixels show through the screen aperture")
        }
    }

    private func enclosedCanvasPixelCount(_ bitmap: NSBitmapImageRep) throws -> Int {
        let data = try #require(bitmap.bitmapData)
        let width = bitmap.pixelsWide, height = bitmap.pixelsHigh
        // The decoded opaque PNG pads RGB to 4 bytes, so samplesPerPixel doesn't give the stride.
        let bytesPerPixel = bitmap.bytesPerRow / width
        var isCanvas = [Bool](repeating: false, count: width * height)
        for index in isCanvas.indices {
            let offset = (index / width) * bitmap.bytesPerRow + (index % width) * bytesPerPixel
            isCanvas[index] = Int(data[offset + 1]) - max(Int(data[offset]), Int(data[offset + 2])) > 128
        }

        var reached = [Bool](repeating: false, count: width * height)
        var stack: [Int] = []
        for x in 0..<width { stack += [x, (height - 1) * width + x] }
        for y in 0..<height { stack += [y * width, y * width + width - 1] }
        while let index = stack.popLast() {
            guard isCanvas[index], !reached[index] else { continue }
            reached[index] = true
            let x = index % width
            if x > 0 { stack.append(index - 1) }
            if x < width - 1 { stack.append(index + 1) }
            if index >= width { stack.append(index - width) }
            if index < (height - 1) * width { stack.append(index + width) }
        }
        return zip(isCanvas, reached).filter { $0 && !$1 }.count
    }

    /// Every frame that claims a rotation must resolve to a real asset, and every frame that does
    /// not must ship its own — this is what catches a deleted imageset or a stale asset slug.
    @Test func everyImageBackedFrameResolvesItsAsset() {
        for frame in DeviceFrameCatalog.allFrames {
            guard let imageName = frame.imageName else { continue }
            #expect(NSImage(named: imageName) != nil, "missing asset \(imageName) for \(frame.id)")
        }
    }

    /// The bezel PNGs are resized independently of the catalog (`tools/optimize-device-frames.py`),
    /// and `DeviceFrameImageView` stretches whatever it loads into the spec's box — so a frame
    /// rescaled to a slightly different aspect ratio wouldn't fail to load, it would silently skew
    /// the art away from the screen aperture on every canvas and every export.
    @Test func everyFrameAssetMatchesItsDeclaredAspectRatio() throws {
        for frame in DeviceFrameCatalog.allFrames {
            guard let imageName = frame.imageName else { continue }
            let image = try #require(NSImage(named: imageName), "missing asset \(imageName)")
            #expect(image.size.width > 0 && image.size.height > 0)

            // Rotated landscape frames reuse the portrait PNG, so the asset is the spec transposed.
            let spec = frame.spec
            let expected = frame.landscapeRotationDegrees == nil
                ? spec.frameWidth / spec.frameHeight
                : spec.frameHeight / spec.frameWidth

            let actual = image.size.width / image.size.height
            #expect(
                abs(actual / expected - 1) < 0.005,
                "\(imageName) is \(image.size.width)x\(image.size.height) (aspect \(actual)), spec expects \(expected)"
            )
        }
    }

    @Test func iphone17ProMax3DFrameUsesBundledUSDZModel() throws {
        let frame = try #require(DeviceFrameCatalog.frame(for: "iphone17promaxmodel-default-portrait"))

        #expect(frame.modelName == "iPhone 17 Pro Max (3D)")
        #expect(frame.isModelBacked)
        #expect(frame.modelSpec?.resourceName == "iphone_17_pro_max")
        #expect(frame.modelSpec?.screenMaterialName == "Display")
        #expect(frame.modelSpec?.screenRenderingMode == .overlayPlane)
        #expect(DeviceFrameCatalog.suggestedSizePreset(forFrameId: frame.id) == "1320x2868")
    }
}
