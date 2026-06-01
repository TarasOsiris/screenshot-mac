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

    func registerMainWindow(_ window: NSWindow) {
        mainWindow = window
    }

    func setMainWindowOpener(_ opener: @escaping () -> Void) {
        mainWindowOpener = opener
    }

    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)

        if let mainWindow {
            if mainWindow.isMiniaturized {
                mainWindow.deminiaturize(nil)
            }
            mainWindow.makeKeyAndOrderFront(nil)
            return
        }

        mainWindowOpener?()
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

struct MainWindowSceneBridge: View {
#if os(macOS)
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MainWindowAccessorView { window in
            AppWindowManager.shared.registerMainWindow(window)
        }
        .task {
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
private struct MainWindowAccessorView: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        resolveWindow(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private func resolveWindow(for view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            onResolve(window)
        }
    }
}
#endif
