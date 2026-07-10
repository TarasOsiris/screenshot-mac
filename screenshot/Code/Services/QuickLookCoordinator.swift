#if os(macOS)
import AppKit
import Quartz

final class QuickLookCoordinator: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookCoordinator()

    private var previewURLs: [URL] = []
    private var edgeKeyMonitor: Any?
    private var panelCloseObserver: NSObjectProtocol?

    func preview(imageAt url: URL) {
        preview(imagesAt: [url], startingAt: 0)
    }

    func preview(imagesAt urls: [URL], startingAt index: Int) {
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        previewURLs = urls
        let clampedIndex = max(0, min(index, urls.count - 1))

        panel.dataSource = self
        panel.delegate = self

        if panel.isVisible {
            panel.reloadData()
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
        panel.currentPreviewItemIndex = clampedIndex
        installEdgeKeyMonitorIfNeeded()
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURLs.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        guard index >= 0 && index < previewURLs.count else { return nil }
        return previewURLs[index] as NSURL
    }

    // QLPreviewPanel handles arrow keys internally and wraps at the ends, so the
    // panel's handle: delegate hook is never called for them. A local NSEvent
    // monitor catches the keys first and drops them at the edges to prevent wrap.
    private func installEdgeKeyMonitorIfNeeded() {
        guard edgeKeyMonitor == nil else { return }
        // Tear the monitor down when the panel closes so it doesn't live for the
        // rest of the app session intercepting every keystroke.
        if let panel = QLPreviewPanel.shared() {
            panelCloseObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: panel,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.teardownEdgeKeyMonitor()
                }
            }
        }
        edgeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let panel = QLPreviewPanel.shared(),
                  panel.isVisible,
                  NSApp.keyWindow === panel
            else { return event }
            let idx = panel.currentPreviewItemIndex
            switch event.keyCode {
            case AppState.kVKLeftArrow where idx <= 0:
                return nil
            case AppState.kVKRightArrow where idx >= QuickLookCoordinator.shared.previewURLs.count - 1:
                return nil
            default:
                return event
            }
        }
    }

    private func teardownEdgeKeyMonitor() {
        if let monitor = edgeKeyMonitor {
            NSEvent.removeMonitor(monitor)
            edgeKeyMonitor = nil
        }
        if let observer = panelCloseObserver {
            NotificationCenter.default.removeObserver(observer)
            panelCloseObserver = nil
        }
    }
}
#else
import QuickLook
import UIKit

/// iOS has no QLPreviewPanel (the macOS floating panel); the equivalent system image viewer
/// is `QLPreviewController`, presented modally over the editor.
final class QuickLookCoordinator: NSObject, QLPreviewControllerDataSource {
    static let shared = QuickLookCoordinator()

    private var previewURLs: [URL] = []

    func preview(imageAt url: URL) {
        preview(imagesAt: [url], startingAt: 0)
    }

    func preview(imagesAt urls: [URL], startingAt index: Int) {
        guard !urls.isEmpty, let presenter = Self.topViewController() else { return }
        previewURLs = urls

        let controller = QLPreviewController()
        controller.dataSource = self
        controller.currentPreviewItemIndex = max(0, min(index, urls.count - 1))
        presenter.present(controller, animated: true)
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        previewURLs.count
    }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem {
        previewURLs[index] as NSURL
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let root = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
            ?? scene?.windows.first?.rootViewController
        var top = root
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
#endif
