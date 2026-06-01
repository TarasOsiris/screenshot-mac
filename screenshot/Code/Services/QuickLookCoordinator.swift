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
                self?.teardownEdgeKeyMonitor()
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
import UIKit

/// iOS has no QLPreviewPanel (a macOS floating panel). Quick Look preview is deferred; this
/// no-op keeps call sites compiling on iPad.
final class QuickLookCoordinator {
    static let shared = QuickLookCoordinator()
    func preview(imageAt url: URL) {}
    func preview(imagesAt urls: [URL], startingAt index: Int) {}
}
#endif
