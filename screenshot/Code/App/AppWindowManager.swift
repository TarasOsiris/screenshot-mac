#if os(macOS)
import AppKit
#endif
import SwiftUI

@MainActor
final class AppWindowManager {
    static let shared = AppWindowManager()

    private var mainWindowOpener: (() -> Void)?
    private init() {}

#if os(macOS)
    private weak var mainWindow: NSWindow?
    private weak var helpWindow: NSWindow?
    private weak var settingsWindow: NSWindow?

    func registerMainWindow(_ window: NSWindow) {
        mainWindow = window
        // The canvas is a WYSIWYG preview of a DeviceRGB PNG, so the backing store is pinned to the
        // space export writes in. Letting it follow a wide-gamut display made two things go wrong:
        // CoreAnimation colour-matched every raster on the main thread inside its commit (~100ms in
        // a scrollbar-drag trace), and the editor showed screenshots more saturated than any export
        // can reproduce. WindowServer still matches the whole surface to the panel, on the GPU.
        window.colorSpace = .sRGB
    }

    func registerHelpWindow(_ window: NSWindow) {
        helpWindow = window
    }

    func registerSettingsWindow(_ window: NSWindow) {
        settingsWindow = window
    }

    func raiseHelpWindow() {
        CrashReportingService.breadcrumb(.app, "Opened Help window")
        raiseWindow(helpWindow)
    }

    func raiseSettingsWindow() {
        CrashReportingService.breadcrumb(.app, "Opened Settings window")
        raiseWindow(settingsWindow)
    }

    func setMainWindowOpener(_ opener: @escaping () -> Void) {
        mainWindowOpener = opener
    }

    func showMainWindow() {
        if let mainWindow {
            raiseWindow(mainWindow)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        mainWindowOpener?()
    }

    private func raiseWindow(_ window: NSWindow?) {
        NSApp.activate(ignoringOtherApps: true)
        guard let window else { return }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
    }
#else
    func setMainWindowOpener(_ opener: @escaping () -> Void) {
        mainWindowOpener = opener
    }

    // iPad uses a single WindowGroup; there is no separate window to raise.
    func showMainWindow() {
        mainWindowOpener?()
    }
#endif
}

/// Registers a SwiftUI scene's backing `NSWindow` with `AppWindowManager` so it
/// can be raised on demand. The `.main` role additionally wires the reopen path.
struct WindowSceneBridge: View {
    enum Role { case main, help, settings }
    let role: Role

#if os(macOS)
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        WindowAccessorView { window in
            switch role {
            case .main: AppWindowManager.shared.registerMainWindow(window)
            case .help: AppWindowManager.shared.registerHelpWindow(window)
            case .settings: AppWindowManager.shared.registerSettingsWindow(window)
            }
        }
        .task {
            guard role == .main else { return }
            AppWindowManager.shared.setMainWindowOpener {
                openWindow(id: AppRootView.windowID)
            }
        }
    }
#else
    var body: some View { EmptyView() }
#endif
}

#if os(macOS)
private struct WindowAccessorView: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        resolveWindow(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private func resolveWindow(for view: NSView) {
        // Deferred: the view has no window until after makeNSView returns.
        Task { @MainActor in
            guard let window = view.window else { return }
            onResolve(window)
        }
    }
}
#endif
