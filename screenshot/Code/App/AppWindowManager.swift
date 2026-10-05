#if os(macOS)
import AppKit
#endif
import SwiftUI

@MainActor
final class AppWindowManager {
    static let shared = AppWindowManager()

    private var mainWindowOpener: (() -> Void)?
    private init() {}

    func setMainWindowOpener(_ opener: @escaping () -> Void) {
        mainWindowOpener = opener
    }

#if os(macOS)
    private weak var mainWindow: NSWindow?
    private weak var helpWindow: NSWindow?
    private weak var settingsWindow: NSWindow?
    private var showProbe: Task<Void, Never>?

    var hasMainWindowOpener: Bool { mainWindowOpener != nil }

    func register(_ window: NSWindow, for role: WindowSceneBridge.Role) {
        switch role {
        case .main:
            mainWindow = window
            // The canvas is a WYSIWYG preview of a DeviceRGB PNG, so the backing store is pinned to the
            // space export writes in. Letting it follow a wide-gamut display made two things go wrong:
            // CoreAnimation colour-matched every raster on the main thread inside its commit (~100ms in
            // a scrollbar-drag trace), and the editor showed screenshots more saturated than any export
            // can reproduce. WindowServer still matches the whole surface to the panel, on the GPU.
            window.colorSpace = .sRGB
        case .help:
            helpWindow = window
        case .settings:
            settingsWindow = window
        }
    }

    func raiseHelpWindow() {
        CrashReportingService.breadcrumb(.app, "Opened Help window")
        raiseWindow(helpWindow)
    }

    /// Opens Help, optionally at a topic. The caller supplies `openWindow` because a `Window`
    /// scene can't carry a value; the deferred raise is here so the runloop quirk it works around
    /// is stated once rather than at every call site.
    func showHelp(_ section: HelpSection? = nil, using openWindow: OpenWindowAction) {
        if let section { HelpWindowNavigation.shared.requestedSection = section }
        openWindow(id: HelpView.windowID)
        // openWindow registers the NSWindow on the next runloop; raise it then so Help comes
        // forward even when it was already open behind another window.
        DispatchQueue.main.async { self.raiseHelpWindow() }
    }

    func raiseSettingsWindow() {
        CrashReportingService.breadcrumb(.app, "Opened Settings window")
        raiseWindow(settingsWindow)
    }

    /// `screen != nil` because a frame restored from an unplugged display is `isVisible` yet shows nothing.
    private var isMainWindowShowing: Bool {
        guard let mainWindow else { return false }
        return mainWindow.isVisible && !mainWindow.isMiniaturized && mainWindow.screen != nil
    }

    /// Gated on the editor itself — AppKit's `hasVisibleWindows` counts Settings/Help too. True = let SwiftUI's default reopen run.
    func reopenMainWindow() -> Bool {
        if !isMainWindowShowing { showMainWindow() }
        return !hasMainWindowOpener
    }

    func showMainWindow() {
        CrashReportingService.breadcrumb(.app, "Showed main window")
        let hadMainWindow = mainWindow != nil
        raiseWindow(mainWindow)
        if isMainWindowShowing { return }
        mainWindowOpener?()
        // openWindow registers its NSWindow on a later runloop turn; no editor after that is our bug.
        showProbe?.cancel()
        showProbe = Task.delayed(1.0) { [self] in
            guard NSApp.isActive, !NSApp.isHidden, !isMainWindowShowing else { return }
            CrashReportingService.report(.mainWindowReopenFailed, extra: [
                "had_main_window": hadMainWindow,
                "has_main_window": mainWindow != nil,
                "has_opener": hasMainWindowOpener,
                "window_count": NSApp.windows.count,
                "visible_window_count": NSApp.windows.filter(\.isVisible).count,
                "main_miniaturized": mainWindow?.isMiniaturized ?? false,
                "main_on_screen": mainWindow?.screen != nil,
            ])
        }
    }

    private func raiseWindow(_ window: NSWindow?) {
        NSApp.activate(ignoringOtherApps: true)
        guard let window else { return }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        if window.screen == nil {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
    }
#else
    // iPad uses a single WindowGroup; there is no separate window to raise.
    func showMainWindow() {
        mainWindowOpener?()
    }
#endif
}

/// Registers a SwiftUI scene's backing `NSWindow` with `AppWindowManager` so it
/// can be raised on demand, and supplies the opener the reopen path falls back to.
struct WindowSceneBridge: View {
    enum Role { case main, help, settings }
    let role: Role

#if os(macOS)
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        WindowAccessorView(role: role)
            .task {
                // Any scene's action can open the editor; the editor's own is preferred once it has appeared.
                guard role == .main || !AppWindowManager.shared.hasMainWindowOpener else { return }
                let openWindow = openWindow
                AppWindowManager.shared.setMainWindowOpener { openWindow(id: AppRootView.windowID) }
            }
    }
#else
    var body: some View { EmptyView() }
#endif
}

#if os(macOS)
private struct WindowAccessorView: NSViewRepresentable {
    let role: WindowSceneBridge.Role

    func makeNSView(context: Context) -> WindowResolvingView {
        let view = WindowResolvingView()
        view.role = role
        return view
    }

    func updateNSView(_ nsView: WindowResolvingView, context: Context) {}
}

/// `viewDidMoveToWindow`, not a deferred check: SwiftUI can build the hierarchy before its NSWindow exists.
private final class WindowResolvingView: NSView {
    var role: WindowSceneBridge.Role = .main
    private weak var resolvedWindow: NSWindow?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, window !== resolvedWindow else { return }
        resolvedWindow = window
        AppWindowManager.shared.register(window, for: role)
    }
}
#endif
