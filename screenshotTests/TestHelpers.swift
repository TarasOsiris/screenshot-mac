import AppKit
import Foundation

func makeTestImage(width: Int, height: Int) -> NSImage {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: width * 4,
        bitsPerPixel: 32
    )!
    let ctx = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    NSColor.systemBlue.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    ctx.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    let image = NSImage(size: NSSize(width: width, height: height))
    image.addRepresentation(bitmap)
    return image
}

/// A solid-color image, for tests that need a known fill (e.g. a white screenshot).
func makeSolidImage(_ color: NSColor, width: Int, height: Int) -> NSImage {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: width * 4,
        bitsPerPixel: 32
    )!
    let ctx = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    color.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    ctx.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    let image = NSImage(size: NSSize(width: width, height: height))
    image.addRepresentation(bitmap)
    return image
}

@testable import Screenshot_Bro

private struct SavedDefaultValue {
    let key: String
    let value: Any?
}

nonisolated(unsafe) private let deterministicDefaultValues: [String: Any] = [
    "defaultScreenshotSize": "1242x2688",
    "defaultTemplateCount": 3,
    "defaultDeviceCategory": DeviceCategory.iphone.rawValue,
    "defaultDeviceFrameId": "",
]

private let deterministicRemovedDefaultKeys = [
    "lastZoomLevel",
    "defaultZoomLevel",
]

@MainActor private var savedDefaultsByTestDirectory: [String: [SavedDefaultValue]] = [:]

/// A state seeded with one default project + row — the historical starting point most
/// tests assume. (The app no longer auto-creates a project on first launch; use
/// `makeEmptyTestState()` to exercise that.)
@MainActor
func makeTestState() -> (AppState, URL) {
    let (state, tempDir) = makeEmptyTestState()
    if state.visibleProjects.isEmpty {
        state.createProject(name: "My App")
        var row = state.makeDefaultRow(
            label: nil,
            width: 1242,
            height: 2688,
            templateCount: 3,
            defaultDeviceCategory: .iphone,
            defaultDeviceFrameId: ""
        )
        row.defaultDeviceFrameId = nil
        state.rows = [row]
        state.selectRow(row.id)
        state.saveAll()
    }
    return (state, tempDir)
}

/// A freshly initialized state with no projects — the real first-launch condition.
@MainActor
func makeEmptyTestState() -> (AppState, URL) {
    let tempDir = makeTemporaryDataDirectory()
    setenv("SCREENSHOT_DATA_DIR", tempDir.path, 1)
    normalizeUserDefaultsForTest(directory: tempDir)
    let state = AppState()
    return (state, tempDir)
}

@MainActor
func cleanupTestState(_ tempDir: URL) {
    unsetenv("SCREENSHOT_DATA_DIR")
    restoreUserDefaultsForTest(directory: tempDir)
    try? FileManager.default.removeItem(at: tempDir)
}

@MainActor
private func normalizeUserDefaultsForTest(directory: URL) {
    let defaults = UserDefaults.standard
    let keys = Array(deterministicDefaultValues.keys) + deterministicRemovedDefaultKeys
    savedDefaultsByTestDirectory[directory.path] = keys.map { key in
        SavedDefaultValue(key: key, value: defaults.object(forKey: key))
    }

    for (key, value) in deterministicDefaultValues {
        defaults.set(value, forKey: key)
    }
    for key in deterministicRemovedDefaultKeys {
        defaults.removeObject(forKey: key)
    }
}

@MainActor
private func restoreUserDefaultsForTest(directory: URL) {
    guard let savedDefaults = savedDefaultsByTestDirectory.removeValue(forKey: directory.path) else {
        return
    }

    let defaults = UserDefaults.standard
    for savedDefault in savedDefaults {
        if let value = savedDefault.value {
            defaults.set(value, forKey: savedDefault.key)
        } else {
            defaults.removeObject(forKey: savedDefault.key)
        }
    }
}

func makeTemporaryDataDirectory(label: String = "screenshot-tests") -> URL {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    let directory = root
        .appendingPathComponent(label, isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}
