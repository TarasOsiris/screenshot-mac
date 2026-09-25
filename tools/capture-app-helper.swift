// Compiled and cached by tools/capture-app.sh — not part of the app target.
// Usage: capture-app-helper <app bundle path> <relaunch 0|1> <out.png>
import AppKit
import CoreGraphics
import ScreenCaptureKit
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("capture-app: \(message)\n".utf8))
    exit(1)
}

func warn(_ message: String) {
    FileHandle.standardError.write(Data("capture-app: warning: \(message)\n".utf8))
}

func waitUntil(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    return condition()
}

func isAlive(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 }

let arguments = CommandLine.arguments
guard arguments.count == 4 else { fail("usage: capture-app-helper <app path> <relaunch 0|1> <out.png>") }
let appURL = URL(fileURLWithPath: arguments[1]).resolvingSymlinksInPath()
let relaunch = arguments[2] == "1"
let outPath = arguments[3]

guard CGPreflightScreenCaptureAccess() else {
    fail("this terminal has no Screen Recording permission (System Settings ▸ Privacy & Security ▸ Screen & System Audio Recording)")
}

// Matched by bundle path, not name: the shipping Screenshot Bro shares the name and bundle id.
func instances() -> [NSRunningApplication] {
    NSWorkspace.shared.runningApplications.filter {
        $0.bundleURL?.resolvingSymlinksInPath() == appURL && isAlive($0.processIdentifier)
    }
}

if relaunch {
    let running = instances()
    // A graceful quit runs willTerminate, which flushes the debounced save; SIGTERM would drop it.
    for app in running where !app.terminate() {
        fail("could not ask pid \(app.processIdentifier) to quit")
    }
    guard waitUntil(30, { running.allSatisfy { !isAlive($0.processIdentifier) } }) else {
        fail("app did not quit within 30 s; not force-killing it so no edits are lost")
    }
}

var target = instances().first
if target == nil {
    final class LaunchResult: @unchecked Sendable { var app: NSRunningApplication?; var error: Error?; var done = false }
    let result = LaunchResult()
    let openConfiguration = NSWorkspace.OpenConfiguration()
    openConfiguration.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(at: appURL, configuration: openConfiguration) { app, error in
        DispatchQueue.main.async { result.app = app; result.error = error; result.done = true }
    }
    guard waitUntil(30, { result.done }) else { fail("launch of \(appURL.path) timed out") }
    guard let app = result.app else { fail("launch failed: \(result.error?.localizedDescription ?? "unknown error")") }
    target = app
} else if let launched = target?.launchDate,
          let built = (try? appURL.appendingPathComponent("Contents/MacOS").resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
          launched < built {
    warn("the running instance predates the latest build; pass --relaunch to capture the new code")
}
guard let app = target else { fail("no running instance of \(appURL.path)") }
let pid = app.processIdentifier

struct Window {
    let id: CGWindowID
    let bounds: CGRect
    let layer: Int
}

func windows(of pid: pid_t) -> [Window] {
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    return info.compactMap { window in
        guard (window[kCGWindowOwnerPID as String] as? Int).map(pid_t.init) == pid,
              let id = window[kCGWindowNumber as String] as? Int,
              let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
              (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
              bounds.width > 1, bounds.height > 1 else { return nil }
        return Window(id: CGWindowID(id), bounds: bounds, layer: window[kCGWindowLayer as String] as? Int ?? 0)
    }
}

func mainWindow(of pid: pid_t) -> Window? {
    windows(of: pid).filter { $0.layer == 0 }.max { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
}

guard waitUntil(30, { mainWindow(of: pid) != nil }) else { fail("no on-screen window for pid \(pid) after 30 s") }

let activate = Process()
activate.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
activate.arguments = ["-e", "tell application \"System Events\" to set frontmost of (first process whose unix id is \(pid)) to true"]
activate.standardOutput = FileHandle.nullDevice
activate.standardError = FileHandle.nullDevice
try? activate.run()
activate.waitUntilExit()
_ = waitUntil(3) { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid }
// Let the window settle after activation (focus rings, sheet animations).
RunLoop.current.run(until: Date().addingTimeInterval(0.5))

guard let main = mainWindow(of: pid) else { fail("the window disappeared before capture") }
// Sheets and popovers are separate windows. Menu bar (24) and status items (25) never belong in the shot.
let captured = windows(of: pid).filter {
    $0.id == main.id || ($0.layer != 24 && $0.layer != 25 && $0.bounds.intersects(main.bounds))
}
let region = captured.reduce(main.bounds) { $0.union($1.bounds) }.integral

final class Box<T>: @unchecked Sendable { var value: T?; var error: Error?; var done = false }

let content = Box<SCShareableContent>()
SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { shareable, error in
    DispatchQueue.main.async { content.value = shareable; content.error = error; content.done = true }
}
guard waitUntil(10, { content.done }), let shareable = content.value else {
    fail("could not list shareable windows: \(content.error?.localizedDescription ?? "timed out")")
}
let capturedIds = Set(captured.map(\.id))
let scWindows = shareable.windows.filter { capturedIds.contains($0.windowID) }
guard !scWindows.isEmpty else { fail("ScreenCaptureKit does not see the app's windows") }
let center = CGPoint(x: main.bounds.midX, y: main.bounds.midY)
guard let display = shareable.displays.first(where: { $0.frame.contains(center) }) ?? shareable.displays.first else {
    fail("no display found")
}
let scale = NSScreen.screens
    .first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == display.displayID }?
    .backingScaleFactor ?? 2

// Composites only the app's own windows, so anything from another app on top of them is left out.
let filter = SCContentFilter(display: display, including: scWindows)
let configuration = SCStreamConfiguration()
configuration.sourceRect = region.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
configuration.width = Int(region.width * scale)
configuration.height = Int(region.height * scale)
configuration.showsCursor = false
configuration.ignoreShadowsDisplay = true

let shot = Box<CGImage>()
SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, error in
    DispatchQueue.main.async { shot.value = image; shot.error = error; shot.done = true }
}
guard waitUntil(10, { shot.done }), let image = shot.value else {
    fail("capture failed: \(shot.error?.localizedDescription ?? "timed out")")
}
guard let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fail("cannot write \(outPath)")
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fail("cannot write \(outPath)") }
print(outPath)
