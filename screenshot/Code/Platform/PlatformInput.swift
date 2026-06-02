import SwiftUI
import OSLog
#if os(macOS)
import AppKit
#else
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
/// iPad has no Finder/save panel, so disk export goes through the system share sheet
/// (Save to Files, AirDrop, etc.). Presents a `UIActivityViewController` over the editor.
enum PlatformShare {
    /// Presents the share sheet for `urls`. Retries briefly while the front-most controller is
    /// mid-transition (e.g. a SwiftUI sheet is still dismissing) so a share triggered from a
    /// sheet's dismiss handler isn't silently dropped by UIKit. `completion` reports whether the
    /// user completed a share action — `false` on cancel or if no presenter ever becomes ready.
    @MainActor
    static func present(urls: [URL], completion: ((Bool) -> Void)? = nil) {
        guard !urls.isEmpty else { completion?(false); return }
        presentWhenReady(urls: urls, attemptsLeft: 20, completion: completion)
    }

    @MainActor
    private static func presentWhenReady(urls: [URL], attemptsLeft: Int, completion: ((Bool) -> Void)?) {
        guard let presenter = readyPresenter() else {
            guard attemptsLeft > 0 else {
                AppLogger.export.warning("Share sheet found no presentable view controller")
                completion?(false)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                presentWhenReady(urls: urls, attemptsLeft: attemptsLeft - 1, completion: completion)
            }
            return
        }
        let activity = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        activity.completionWithItemsHandler = { _, completed, _, _ in completion?(completed) }
        // iPad requires a popover anchor; center it over the presenter.
        if let popover = activity.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        presenter.present(activity, animated: true)
    }

    /// The front-most controller that can present right now: in a window and not itself mid
    /// present/dismiss. Returns nil while a sheet is animating away, so the caller retries.
    private static func readyPresenter() -> UIViewController? {
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
}

/// Canonical offscreen image renderer for iPad: non-opaque, 1x scale (so pixel dimensions
/// match model space, which the export/crop math relies on). The `draw` block runs with the
/// UIKit graphics context current, so `UIImage.draw(in:)` etc. work inside it.
enum PlatformImageRenderer {
    static func image(size: CGSize, opaque: Bool = false, _ draw: () -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = opaque
        format.scale = 1
        let safe = (size.width > 0 && size.height > 0) ? size : CGSize(width: 1, height: 1)
        return UIGraphicsImageRenderer(size: safe, format: format).image { _ in draw() }
    }
}
#endif
