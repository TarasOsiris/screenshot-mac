import SwiftUI
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
    @MainActor
    static func present(urls: [URL]) {
        guard !urls.isEmpty, let presenter = topViewController() else { return }
        let activity = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        // iPad requires a popover anchor; center it over the presenter.
        if let popover = activity.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        presenter.present(activity, animated: true)
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
