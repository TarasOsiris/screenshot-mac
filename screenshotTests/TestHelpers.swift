import AppKit
import Foundation

private let testStateLock = NSLock()

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

@testable import Screenshot_Bro

@MainActor
func makeTestState() -> (AppState, URL) {
    // AppState test fixtures rely on a process-wide env override.
    // Hold a lock for the full fixture lifetime so parallel tests do not race.
    testStateLock.lock()
    let tempDir = makeTemporaryDataDirectory()
    setenv("SCREENSHOT_DATA_DIR", tempDir.path, 1)
    let state = AppState()
    return (state, tempDir)
}

func cleanupTestState(_ tempDir: URL) {
    unsetenv("SCREENSHOT_DATA_DIR")
    try? FileManager.default.removeItem(at: tempDir)
    testStateLock.unlock()
}

func makeTemporaryDataDirectory(label: String = "screenshot-tests") -> URL {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    let directory = root
        .appendingPathComponent(label, isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}
