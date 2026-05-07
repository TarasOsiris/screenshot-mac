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
