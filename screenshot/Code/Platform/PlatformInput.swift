import OSLog
import SwiftUI
#if os(macOS)
import AppKit
#else
import Photos
import UIKit
#endif

/// Synchronous keyboard-modifier state. macOS reads the live NSEvent flags; iPad has no
/// equivalent global query, so modifiers default to off (shift-constrain / option-duplicate
/// are macOS-only conveniences for this foundation pass).
enum PlatformModifiers {
    static var shiftDown: Bool {
        #if os(macOS)
        NSEvent.modifierFlags.contains(.shift)
        #else
        false
        #endif
    }

    static var optionDown: Bool {
        #if os(macOS)
        NSEvent.modifierFlags.contains(.option)
        #else
        false
        #endif
    }
}

enum PlatformReveal {
    /// Reveal files in Finder (macOS). No-op on iPad for this foundation pass.
    static func inFileViewer(_ urls: [URL]) {
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting(urls)
        #endif
    }
}

enum PlatformPasteboard {
    static func copyString(_ string: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #else
        UIPasteboard.general.string = string
        #endif
    }
}

#if os(iOS)
/// Resolves the front-most UIKit controller that can present a modal right now, retrying while
/// a SwiftUI sheet is mid-transition. Shared by every iPad presenter (share sheet, Files
/// document picker) so a present triggered from a sheet handler isn't silently dropped.
enum PlatformPresenter {
    /// The front-most controller that can present right now: in a window and not itself mid
    /// present/dismiss. Returns nil while a sheet is animating away, so the caller retries.
    static func ready() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let root = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
            ?? scene?.windows.first?.rootViewController
        var top = root
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        guard let candidate = top,
              candidate.view.window != nil,
              !candidate.isBeingPresented,
              !candidate.isBeingDismissed,
              candidate.presentedViewController == nil else {
            return nil
        }
        return candidate
    }

    /// Awaits a presenter, re-checking every 0.1s up to `retries` times (nil once the
    /// window never settles). `ready()` returns nil while a sheet animates away, hence the
    /// polling — UIKit offers no notification for "the top controller can present now".
    @MainActor
    static func waitForReady(retries: Int = 20) async -> UIViewController? {
        for attempt in 0...retries {
            if let presenter = ready() { return presenter }
            guard attempt < retries else { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        AppLogger.export.warning("No presentable view controller for modal")
        return nil
    }

    /// Centers a popover over the presenter with no arrow — required for iPad action-style modals.
    static func anchorPopover(_ controller: UIViewController, in presenter: UIViewController) {
        guard let popover = controller.popoverPresentationController else { return }
        popover.sourceView = presenter.view
        popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
        popover.permittedArrowDirections = []
    }
}

/// iPad has no Finder/save panel, so disk export goes through the system share sheet
/// (AirDrop, Mail, Print, etc.). Presents a `UIActivityViewController` over the editor.
enum PlatformShare {
    /// Presents the share sheet for `urls`. `completion` reports whether the user completed a
    /// share action — `false` on cancel or if no presenter ever becomes ready.
    @MainActor
    static func present(urls: [URL], completion: ((Bool) -> Void)? = nil) {
        guard !urls.isEmpty else { completion?(false); return }
        // Present inline when a presenter already exists — the usual case, since this runs from
        // an explicit tap. Only an unsettled window pays for the await.
        if let presenter = PlatformPresenter.ready() {
            show(urls: urls, in: presenter, completion: completion)
        } else {
            Task {
                guard let presenter = await PlatformPresenter.waitForReady() else {
                    completion?(false)
                    return
                }
                show(urls: urls, in: presenter, completion: completion)
            }
        }
    }

    @MainActor
    private static func show(urls: [URL], in presenter: UIViewController, completion: ((Bool) -> Void)?) {
        let activity = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        activity.completionWithItemsHandler = { _, completed, _, _ in completion?(completed) }
        PlatformPresenter.anchorPopover(activity, in: presenter)
        presenter.present(activity, animated: true)
    }
}

/// "Save to Files" on iPad: a document picker in export mode that copies the rendered files to a
/// user-chosen Files location. The delegate is retained until the picker finishes (UIKit does not
/// retain it), then released.
enum PlatformDocumentExport {
    private static var retainedDelegate: DocumentExportDelegate?

    @MainActor
    static func present(urls: [URL], completion: ((Bool) -> Void)? = nil) {
        guard !urls.isEmpty else { completion?(false); return }
        if let presenter = PlatformPresenter.ready() {
            show(urls: urls, in: presenter, completion: completion)
        } else {
            Task {
                guard let presenter = await PlatformPresenter.waitForReady() else {
                    completion?(false)
                    return
                }
                show(urls: urls, in: presenter, completion: completion)
            }
        }
    }

    @MainActor
    private static func show(urls: [URL], in presenter: UIViewController, completion: ((Bool) -> Void)?) {
        let picker = UIDocumentPickerViewController(forExporting: urls, asCopy: true)
        let delegate = DocumentExportDelegate { completed in
            retainedDelegate = nil
            completion?(completed)
        }
        retainedDelegate = delegate
        picker.delegate = delegate
        PlatformPresenter.anchorPopover(picker, in: presenter)
        presenter.present(picker, animated: true)
    }
}

private final class DocumentExportDelegate: NSObject, UIDocumentPickerDelegate {
    private let completion: (Bool) -> Void
    init(completion: @escaping (Bool) -> Void) { self.completion = completion }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        completion(true)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        completion(false)
    }
}

/// "Save to Gallery" on iPad: adds the rendered images to the Photos library. Requires
/// `NSPhotoLibraryAddUsageDescription`. Add-only authorization keeps the prompt minimal.
enum PlatformPhotoLibrary {
    enum SaveError: LocalizedError {
        case accessDenied
        nonisolated var errorDescription: String? {
            String(localized: "Allow photo access in Settings to save to your gallery.")
        }
    }

    /// Saves each file URL as a photo; `completion` is called on the main actor.
    /// Uses the async PhotoKit API (like `NotificationService`) so no MainActor-isolated closure
    /// is handed to PhotoKit's background queue. With `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
    /// the completion-handler form would run a MainActor closure off-main and trap; the change
    /// block is marked `@Sendable` for the same reason.
    @MainActor
    static func save(fileURLs: [URL], completion: @escaping (Bool, Error?) -> Void) {
        guard !fileURLs.isEmpty else { completion(false, nil); return }
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                completion(false, SaveError.accessDenied)
                return
            }
            do {
                try await PHPhotoLibrary.shared().performChanges { @Sendable in
                    for url in fileURLs {
                        PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: url, options: nil)
                    }
                }
                completion(true, nil)
            } catch {
                completion(false, error)
            }
        }
    }
}

/// Canonical offscreen image renderer for iPad: non-opaque, 1x scale (so pixel dimensions
/// match model space, which the export/crop math relies on). The `draw` block runs with the
/// UIKit graphics context current, so `UIImage.draw(in:)` etc. work inside it.
nonisolated enum PlatformImageRenderer {
    static func image(size: CGSize, opaque: Bool = false, scale: CGFloat = 1, _ draw: () -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = opaque
        format.scale = scale
        let safe = (size.width > 0 && size.height > 0) ? size : CGSize(width: 1, height: 1)
        return UIGraphicsImageRenderer(size: safe, format: format).image { _ in draw() }
    }
}
#endif
