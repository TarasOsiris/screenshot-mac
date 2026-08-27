import SwiftUI

struct ShapeSelectionActionsSection: View {
    let canBringToFront: Bool
    let canSendToBack: Bool
    let onBringToFront: () -> Void
    let onSendToBack: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ShapePropertiesSection {
            HStack(spacing: 4) {
                // Shortcut hints only make sense on macOS; on iOS they'd be read aloud by VoiceOver.
                #if os(macOS)
                ActionButton(icon: "square.3.layers.3d.top.filled", tooltip: "Bring to front (⇧⌘])", frameSize: UIMetrics.IconButton.frameSize, disabled: !canBringToFront) {
                    onBringToFront()
                }

                ActionButton(icon: "square.3.layers.3d.bottom.filled", tooltip: "Send to back (⇧⌘[)", frameSize: UIMetrics.IconButton.frameSize, disabled: !canSendToBack) {
                    onSendToBack()
                }

                ActionButton(icon: "doc.on.doc", tooltip: "Duplicate (⌘D)", frameSize: UIMetrics.IconButton.frameSize) {
                    onDuplicate()
                }

                ActionButton(icon: "trash", tooltip: "Delete (⌫)", frameSize: UIMetrics.IconButton.frameSize, isDestructive: true) {
                    onDelete()
                }
                #else
                ActionButton(icon: "square.3.layers.3d.top.filled", tooltip: "Bring to front", frameSize: UIMetrics.IconButton.frameSize, disabled: !canBringToFront) {
                    onBringToFront()
                }

                ActionButton(icon: "square.3.layers.3d.bottom.filled", tooltip: "Send to back", frameSize: UIMetrics.IconButton.frameSize, disabled: !canSendToBack) {
                    onSendToBack()
                }

                ActionButton(icon: "doc.on.doc", tooltip: "Duplicate", frameSize: UIMetrics.IconButton.frameSize) {
                    onDuplicate()
                }

                ActionButton(icon: "trash", tooltip: "Delete", frameSize: UIMetrics.IconButton.frameSize, isDestructive: true) {
                    onDelete()
                }
                #endif
            }
        }
    }
}
