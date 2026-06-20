import Testing
import Foundation
@testable import Screenshot_Bro

struct StorePlatformTests {

    private func row(label: String = "", deviceCategories: [DeviceCategory] = []) -> ScreenshotRow {
        let shapes = deviceCategories.map { CanvasShapeModel(type: .device, deviceCategory: $0) }
        return ScreenshotRow(label: label, shapes: shapes)
    }

    // MARK: - DeviceCategory.storePlatform

    @Test func deviceCategoryMapsToCorrectPlatform() {
        #expect(DeviceCategory.iphone.storePlatform == .apple)
        #expect(DeviceCategory.ipadPro11.storePlatform == .apple)
        #expect(DeviceCategory.ipadPro13.storePlatform == .apple)
        #expect(DeviceCategory.macbook.storePlatform == .apple)
        #expect(DeviceCategory.androidPhone.storePlatform == .android)
        #expect(DeviceCategory.pixel9.storePlatform == .android)
        #expect(DeviceCategory.androidTablet.storePlatform == .android)
        #expect(DeviceCategory.invisible.storePlatform == nil)
    }

    // MARK: - Name-only inference

    @Test func nameInfersApple() {
        #expect(row(label: "iOS").inferredStorePlatform == .apple)
        #expect(row(label: "iPhone Screenshots").inferredStorePlatform == .apple)
        #expect(row(label: "iPad Pro").inferredStorePlatform == .apple)
        #expect(row(label: "App Store").inferredStorePlatform == .apple)
    }

    @Test func nameInfersAndroid() {
        #expect(row(label: "Android").inferredStorePlatform == .android)
        #expect(row(label: "Pixel 9").inferredStorePlatform == .android)
        #expect(row(label: "Google Play").inferredStorePlatform == .android)
    }

    @Test func ambiguousOrNeutralNamesInferNil() {
        #expect(row(label: "Display").inferredStorePlatform == nil)  // must not match "play"
        #expect(row(label: "").inferredStorePlatform == nil)
        #expect(row(label: "Feature graphic").inferredStorePlatform == nil)
        #expect(row(label: "iOS and Android").inferredStorePlatform == nil)  // both → nil
    }

    // MARK: - Frame-only inference

    @Test func frameInfersPlatform() {
        #expect(row(deviceCategories: [.iphone]).inferredStorePlatform == .apple)
        #expect(row(deviceCategories: [.iphone, .ipadPro13]).inferredStorePlatform == .apple)
        #expect(row(deviceCategories: [.androidPhone]).inferredStorePlatform == .android)
        #expect(row(deviceCategories: [.iphone, .androidPhone]).inferredStorePlatform == nil)  // mixed → nil
    }

    @Test func invisibleFramesAreSilent() {
        #expect(row(label: "Android", deviceCategories: [.invisible]).inferredStorePlatform == .android)
    }

    // MARK: - Precedence

    @Test func deviceFramesWinOverName() {
        let r = row(label: "iOS", deviceCategories: [.androidPhone])
        #expect(r.inferredStorePlatform == .android)
    }

    @Test func nameUsedWhenFramesMixed() {
        let r = row(label: "iOS", deviceCategories: [.iphone, .androidPhone])
        #expect(r.inferredStorePlatform == .apple)
    }
}
