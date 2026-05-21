import AppKit
import Quartz

final class QuickLookCoordinator: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookCoordinator()

    private var previewURLs: [URL] = []

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
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURLs.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        guard index >= 0 && index < previewURLs.count else { return nil }
        return previewURLs[index] as NSURL
    }
}
