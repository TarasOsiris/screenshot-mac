import Foundation
@testable import Screenshot_Bro
import Testing

// These raw values are the UserDefaults keys a shipping user's preferences are stored under.
// Renaming a constant is harmless; changing the string it holds silently resets that preference
// for everyone who has already set it, with no build error and no failing behavioural test.
// So the strings are pinned literally here — if one of these fails, the fix is to restore the
// value, not to update the expectation.
struct AppSettingsKeysTests {

    @Test func keyRawValuesAreStable() {
        #expect(AppSettingsKeys.appearance == "appearance")
        #expect(AppSettingsKeys.appLanguageOverride == "appLanguageOverride")
        #expect(AppSettingsKeys.defaultScreenshotSize == "defaultScreenshotSize")
        #expect(AppSettingsKeys.exportFormat == "exportFormat")
        #expect(AppSettingsKeys.exportCustomSuffix == "exportCustomSuffix")
        #expect(AppSettingsKeys.openExportFolderOnSuccess == "openExportFolderOnSuccess")
        #expect(AppSettingsKeys.defaultTemplateCount == "defaultTemplateCount")
        #expect(AppSettingsKeys.defaultZoomLevel == "defaultZoomLevel")
        #expect(AppSettingsKeys.confirmBeforeDeleting == "confirmBeforeDeleting")
        #expect(AppSettingsKeys.defaultDeviceCategory == "defaultDeviceCategory")
        #expect(AppSettingsKeys.defaultDeviceFrameId == "defaultDeviceFrameId")
        #expect(AppSettingsKeys.projectSortOrder == "projectSortOrder")
        #expect(AppSettingsKeys.selectionInspector == "selectionInspectorEnabled")
        #expect(AppSettingsKeys.betaABTesting == "betaABTestingEnabled")
        #expect(AppSettingsKeys.lastZoomLevel == "lastZoomLevel")
        #expect(AppSettingsKeys.installId == "installId")
        #expect(AppSettingsKeys.installFirstVersion == "installFirstVersion")
        #expect(AppSettingsKeys.analyticsAliasedStoreUserId == "analyticsAliasedStoreUserId")
    }

    @Test func defaultsAreStable() {
        #expect(AppSettingsKeys.Default.appearance == "auto")
        #expect(AppSettingsKeys.Default.defaultScreenshotSize == "1242x2688")
        #expect(AppSettingsKeys.Default.exportFormat == "png")
        #expect(AppSettingsKeys.Default.defaultTemplateCount == 3)
        #expect(AppSettingsKeys.Default.defaultZoomLevel == 1.0)
        #expect(AppSettingsKeys.Default.confirmBeforeDeleting)
        #expect(AppSettingsKeys.Default.openExportFolderOnSuccess)
        #expect(AppSettingsKeys.Default.defaultDeviceCategory == "iphone")
        #expect(AppSettingsKeys.Default.projectSortOrder == "creation")
        #expect(!AppSettingsKeys.Default.selectionInspector, "The selection inspector is opt-in")
    }

    /// Two keys differing only in case or by a typo would each read a different stored value
    /// while looking interchangeable at the call site.
    @Test func keysAreDistinct() {
        let keys = [
            AppSettingsKeys.appearance, AppSettingsKeys.appLanguageOverride,
            AppSettingsKeys.defaultScreenshotSize, AppSettingsKeys.exportFormat,
            AppSettingsKeys.exportCustomSuffix, AppSettingsKeys.openExportFolderOnSuccess,
            AppSettingsKeys.defaultTemplateCount, AppSettingsKeys.defaultZoomLevel,
            AppSettingsKeys.confirmBeforeDeleting, AppSettingsKeys.defaultDeviceCategory,
            AppSettingsKeys.defaultDeviceFrameId, AppSettingsKeys.projectSortOrder,
            AppSettingsKeys.lastZoomLevel, AppSettingsKeys.selectionInspector, AppSettingsKeys.betaABTesting,
        ]
        #expect(Set(keys).count == keys.count)
        #expect(keys.allSatisfy { !$0.isEmpty })
    }

    /// `defaultDeviceCategory`'s default must name a real case, or a fresh install falls back
    /// to no device at all rather than to an iPhone.
    @Test func defaultDeviceCategoryNamesARealCase() {
        #expect(DeviceCategory(rawValue: AppSettingsKeys.Default.defaultDeviceCategory) != nil)
    }

    /// Until 4.16 these were inline `@AppStorage` literals in the three inspector views, five of
    /// them copy-pasted so single- and multi-selection shared a section. They are now enum cases,
    /// which is a rename away from re-expanding every section a user has collapsed.
    @Test func inspectorSectionKeyRawValuesAreStable() {
        #expect(InspectorSectionID.rowSize.rawValue == "inspectorSizeExpanded")
        #expect(InspectorSectionID.rowDevice.rawValue == "inspectorDeviceExpanded")
        #expect(InspectorSectionID.rowBackground.rawValue == "inspectorBackgroundExpanded")
        #expect(InspectorSectionID.rowShapes.rawValue == "inspectorShapesExpanded")
        #expect(InspectorSectionID.rowVisibility.rawValue == "inspectorVisibilityExpanded")
        #expect(InspectorSectionID.rowOther.rawValue == "inspectorOtherExpanded")
        #expect(InspectorSectionID.shapeGeometry.rawValue == "inspectorShapeGeometryExpanded")
        #expect(InspectorSectionID.shapeDevice.rawValue == "inspectorShapeDeviceExpanded")
        #expect(InspectorSectionID.shape3D.rawValue == "inspectorShape3DExpanded")
        #expect(InspectorSectionID.shapeText.rawValue == "inspectorShapeTextExpanded")
        #expect(InspectorSectionID.shapeTextBackground.rawValue == "inspectorShapeTextBackgroundExpanded")
        #expect(InspectorSectionID.shapeMedia.rawValue == "inspectorShapeMediaExpanded")
        #expect(InspectorSectionID.shapeAppearance.rawValue == "inspectorShapeAppearanceExpanded")
        #expect(InspectorSectionID.shapeFill.rawValue == "inspectorShapeFillExpanded")
        #expect(InspectorSectionID.shapeOutline.rawValue == "inspectorShapeOutlineExpanded")
        #expect(InspectorSectionID.shapeShadow.rawValue == "inspectorShapeShadowExpanded")
        #expect(InspectorSectionID.shapeLocalization.rawValue == "inspectorShapeLocalizationExpanded")
        // An 18th case would otherwise ship unpinned, which is how a key drifts unnoticed.
        #expect(InspectorSectionID.allCases.count == 17)
    }

    /// The expansion a fresh install opens with. Both closed sections are secondary surfaces that
    /// would otherwise push the sections below them off-screen on every selection.
    @Test func inspectorSectionsStartExpandedExceptTheSecondaryOnes() {
        let closed = InspectorSectionID.allCases.filter { !$0.startsExpanded }
        #expect(Set(closed) == [.shape3D, .shapeTextBackground])
    }
}
