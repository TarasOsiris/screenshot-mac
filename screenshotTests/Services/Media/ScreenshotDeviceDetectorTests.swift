import AppKit
@testable import Screenshot_Bro
import Testing

@MainActor
struct ScreenshotDeviceDetectorTests {
    @Test(arguments: [(2007, 2853), (2853, 2007), (1398, 2034), (2034, 1398)])
    func iphoneDuoSizesAreIPhones(width: Int, height: Int) {
        #expect(ScreenshotDeviceDetector.detectScreenshotDevice(makeTestImage(width: width, height: height)) == .iphone)
    }

    @Test func duoScreenshotsLandInTheMatchingDuoFrame() {
        let row = ScreenshotRow(defaultDeviceFrameId: "iphone17-black-portrait")
        let inner = ScreenshotDeviceDetector.preferredImportFrame(for: makeTestImage(width: 2007, height: 2853), in: row, detectedCategory: .iphone)
        let innerLandscape = ScreenshotDeviceDetector.preferredImportFrame(for: makeTestImage(width: 2853, height: 2007), in: row, detectedCategory: .iphone)
        let outer = ScreenshotDeviceDetector.preferredImportFrame(for: makeTestImage(width: 1398, height: 2034), in: row, detectedCategory: .iphone)

        #expect(groupId(inner) == "iphoneduo")
        #expect(inner?.isLandscape == false)
        #expect(groupId(innerLandscape) == "iphoneduo")
        #expect(innerLandscape?.isLandscape == true)
        #expect(groupId(outer) == "iphoneduoclosed")
    }

    private func groupId(_ frame: DeviceFrame?) -> String? {
        frame.flatMap { DeviceFrameCatalog.group(forFrameId: $0.id)?.id }
    }

    @Test func dedicatedFrameKeepsTheCurrentDuoColor() {
        let frame = DeviceFrameCatalog.dedicatedFrame(forScreenshotWidth: 1398, height: 2034, matchingColorOf: "iphoneduo-starwhite-portrait")
        #expect(frame?.id == "iphoneduoclosed-starwhite-portrait")
    }

    @Test func ordinarySizesHaveNoDedicatedFrame() {
        #expect(DeviceFrameCatalog.dedicatedFrame(forScreenshotWidth: 1320, height: 2868) == nil)
    }

    @Test func duoPresetsSuggestIPhoneAndDuoFramesSuggestTheirSize() {
        #expect(DeviceCategory.suggestedCategory(forSizePreset: "2007x2853") == .iphone)
        #expect(DeviceCategory.suggestedCategory(forSizePreset: "1398x2034") == .iphone)
        #expect(DeviceFrameCatalog.suggestedSizePreset(forFrameId: "iphoneduo-nightsky-portrait") == "2007x2853")
        #expect(DeviceFrameCatalog.suggestedSizePreset(forFrameId: "iphoneduoclosed-nightsky-portrait") == "1398x2034")
    }
}
