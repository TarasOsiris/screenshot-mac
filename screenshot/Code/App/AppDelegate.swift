#if os(macOS)
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    #if DIRECT_DISTRIBUTION
    let updater = DirectUpdater.shared
    weak var purchaseService: PurchaseService? {
        didSet { redeemPendingURLs() }
    }
    /// A cold launch from a redemption link delivers the URL before the main window's task has
    /// configured RevenueCat.
    private var pendingURLs: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        pendingURLs += urls
        AppWindowManager.shared.showMainWindow()
        redeemPendingURLs()
    }

    private func redeemPendingURLs() {
        guard let purchaseService, !pendingURLs.isEmpty else { return }
        let urls = pendingURLs
        pendingURLs = []
        Task {
            for url in urls { await purchaseService.redeem(url) }
        }
    }
    #endif

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return false }
        CrashReportingService.breadcrumb(.app, "Reopened from Dock")
        AppWindowManager.shared.showMainWindow()
        return true
    }
}
#endif
