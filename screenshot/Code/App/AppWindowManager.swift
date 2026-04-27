import AppKit
import SwiftUI

@MainActor
final class AppWindowManager {
    static let shared = AppWindowManager()

    private weak var mainWindow: NSWindow?
    private var mainWindowOpener: (() -> Void)?

    private init() {}

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
}

struct MainWindowSceneBridge: View {
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
}

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
