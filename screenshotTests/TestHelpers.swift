import AppKit
import Foundation
import Testing

/// Shared bitmap boilerplate behind the image factories below.
private func makeBitmapImage(width: Int, height: Int, draw: (NSRect) -> Void) -> NSImage {
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
    draw(NSRect(x: 0, y: 0, width: width, height: height))
    ctx.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    let image = NSImage(size: NSSize(width: width, height: height))
    image.addRepresentation(bitmap)
    return image
}

func makeTestImage(width: Int, height: Int) -> NSImage {
    makeBitmapImage(width: width, height: height) { rect in
        NSColor.systemBlue.setFill()
        rect.fill()
    }
}

/// Half opaque, half fully transparent — so a re-encode that flattens alpha onto white is
/// distinguishable from one that preserves it.
func makeTransparentTestImage(width: Int, height: Int) -> NSImage {
    makeBitmapImage(width: width, height: height) { rect in
        NSColor.clear.setFill()
        rect.fill()
        NSColor.systemPink.setFill()
        NSRect(x: 0, y: 0, width: rect.width, height: rect.height / 2).fill()
    }
}

/// A solid-color image, for tests that need a known fill (e.g. a white screenshot).
func makeSolidImage(_ color: NSColor, width: Int, height: Int) -> NSImage {
    makeBitmapImage(width: width, height: height) { rect in
        color.setFill()
        rect.fill()
    }
}

@testable import Screenshot_Bro

private struct SavedDefaultValue {
    let key: String
    let value: Any?
}

nonisolated(unsafe) private let deterministicDefaultValues: [String: Any] = [
    AppSettingsKeys.defaultScreenshotSize: "1242x2688",
    AppSettingsKeys.defaultTemplateCount: 3,
    AppSettingsKeys.defaultDeviceCategory: DeviceCategory.iphone.rawValue,
    AppSettingsKeys.defaultDeviceFrameId: "",
]

private let deterministicRemovedDefaultKeys = [
    AppSettingsKeys.lastZoomLevel,
    AppSettingsKeys.defaultZoomLevel,
]

@MainActor private var savedDefaultsByTestDirectory: [String: [SavedDefaultValue]] = [:]

/// A state seeded with one default project + row — the historical starting point most
/// tests assume. (The app no longer auto-creates a project on first launch; use
/// `makeEmptyTestState()` to exercise that.)
@MainActor
func makeTestState(fonts: CustomFontLibrary = CustomFontLibrary()) -> (AppState, URL) {
    let (state, tempDir) = makeEmptyTestState(fonts: fonts)
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
/// Why every suite that calls this is `@Suite(.serialized)`:
///
/// `SCREENSHOT_DATA_DIR` is a process-global env var and `UserDefaults.standard` is a
/// process-global store, so two tests running concurrently would clobber each other's data
/// directory — and a debounced save landing after a test unsets the var would write into the
/// user's real (iCloud) project store. `PersistenceService.isRunningUnderXCTest` is the backstop
/// for that, not a licence to parallelise.
///
/// Making these parallel-safe means injecting the data root *and* a UserDefaults suite through
/// `PersistenceService`, which is a static namespace with ~126 call sites. That has been
/// considered and rejected: the whole suite runs in about 20 seconds, so the change buys a few
/// seconds of wall clock in exchange for a wide edit to the one subsystem where a mistake costs
/// users their projects. Don't remove `.serialized` without doing that injection first.
///
/// Know what `.serialized` does and doesn't buy: it serializes tests **within** a suite, not
/// suites against each other. Two different suites that both call this can still overlap. That
/// hasn't bitten in practice (each holds the env var only briefly, and the XCTest backstop catches
/// a late save), but it is the reason the residual `batchImport` flakiness is a real hazard rather
/// than a mystery. Injection is the fix; the trait is the mitigation.
@MainActor
func makeEmptyTestState(fonts: CustomFontLibrary = CustomFontLibrary()) -> (AppState, URL) {
    let tempDir = makeTemporaryDataDirectory()
    setenv("SCREENSHOT_DATA_DIR", tempDir.path, 1)
    normalizeUserDefaultsForTest(directory: tempDir)
    let state = AppState(fonts: fonts)
    return (state, tempDir)
}

/// `makeEmptyTestState` with a chance to lay files down first, for the paths that only run inside
/// `AppState.init` (index load, and the rebuild that happens when it finds no index).
@MainActor
func makeTestStateSeedingDataDirectory(
    fonts: CustomFontLibrary = CustomFontLibrary(),
    seed: (URL) throws -> Void
) rethrows -> (AppState, URL) {
    let tempDir = makeTemporaryDataDirectory()
    setenv("SCREENSHOT_DATA_DIR", tempDir.path, 1)
    normalizeUserDefaultsForTest(directory: tempDir)
    do {
        try seed(tempDir)
    } catch {
        cleanupTestState(tempDir)
        throw error
    }
    return (AppState(fonts: fonts), tempDir)
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

/// Counts main-actor turns, for tests asserting that a long operation actually yields.
@MainActor
final class MainActorTicker {
    var ticks = 0
}

/// Fails if `work` runs inline on the main actor: queued main-actor work (progress updates, window
/// dragging) only gets a slot if awaiting `work` actually suspends. This target builds with
/// `NonisolatedNonsendingByDefault`, under which a plain `nonisolated async` inherits the caller's
/// actor and never yields — the shape that shipped as a multi-second hang in 4.0 (108).
@MainActor
func expectSuspendsMainActor(
    _ work: () async throws -> Void,
    sourceLocation: SourceLocation = #_sourceLocation
) async rethrows {
    let ticker = MainActorTicker()
    Task { @MainActor in ticker.ticks += 1 }
    #expect(ticker.ticks == 0, sourceLocation: sourceLocation)
    try await work()
    #expect(ticker.ticks > 0, sourceLocation: sourceLocation)
}

/// Wraps plain images as import sources, the common case in batch-import tests.
func importSources(_ images: [NSImage]) -> [ImageImportSource] {
    images.map { ImageImportSource(image: $0) }
}
