import SwiftUI

/// Bring to front, send to back, duplicate and delete for the current shape selection.
struct ShapeSelectionActionButtons: View {
    var canBringToFront = true
    var canSendToBack = true
    let onBringToFront: () -> Void
    let onSendToBack: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    // Shortcut hints only make sense on macOS; on iOS they'd be read aloud by VoiceOver.
    #if os(macOS)
    private static let bringToFrontTooltip: LocalizedStringKey = "Bring to front (⇧⌘])"
    private static let sendToBackTooltip: LocalizedStringKey = "Send to back (⇧⌘[)"
    private static let duplicateTooltip: LocalizedStringKey = "Duplicate (⌘D)"
    private static let deleteTooltip: LocalizedStringKey = "Delete (⌫)"
    #else
    private static let bringToFrontTooltip: LocalizedStringKey = "Bring to front"
    private static let sendToBackTooltip: LocalizedStringKey = "Send to back"
    private static let duplicateTooltip: LocalizedStringKey = "Duplicate"
    private static let deleteTooltip: LocalizedStringKey = "Delete"
    #endif

    var body: some View {
        HStack(spacing: 4) {
            ActionButton(icon: "square.3.layers.3d.top.filled", tooltip: Self.bringToFrontTooltip, frameSize: UIMetrics.IconButton.frameSize, disabled: !canBringToFront, action: onBringToFront)
            ActionButton(icon: "square.3.layers.3d.bottom.filled", tooltip: Self.sendToBackTooltip, frameSize: UIMetrics.IconButton.frameSize, disabled: !canSendToBack, action: onSendToBack)
            ActionButton(icon: "doc.on.doc", tooltip: Self.duplicateTooltip, frameSize: UIMetrics.IconButton.frameSize, action: onDuplicate)
            ActionButton(icon: "trash", tooltip: Self.deleteTooltip, frameSize: UIMetrics.IconButton.frameSize, isDestructive: true, action: onDelete)
        }
    }
}
