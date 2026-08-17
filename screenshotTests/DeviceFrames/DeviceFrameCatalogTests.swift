import CoreGraphics
import SwiftUI
import Testing
@testable import Screenshot_Bro

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

    @Test func firstPortraitFrameIdUsesFirstCatalogMatchPerCategory() {
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

    /// Every frame that claims a rotation must resolve to a real asset, and every frame that does
    /// not must ship its own — this is what catches a deleted imageset or a stale asset slug.
    @Test func everyImageBackedFrameResolvesItsAsset() {
        for frame in DeviceFrameCatalog.allFrames {
            guard let imageName = frame.imageName else { continue }
            #expect(NSImage(named: imageName) != nil, "missing asset \(imageName) for \(frame.id)")
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
