#if os(macOS)
import AppKit
#endif
import Foundation
import Observation

/// Shapes and text styles copied inside the app. Shapes never round-trip through the system
/// pasteboard; it is only consulted to tell whether something newer was copied elsewhere.
@Observable
final class ShapeClipboard {
    private(set) var shapes: [CanvasShapeModel] = []
    var textStyle: TextStyle?

    @ObservationIgnored private var pasteboardChangeCount = 0

    func copy(_ shapes: [CanvasShapeModel]) {
        self.shapes = shapes
        #if os(macOS)
        pasteboardChangeCount = NSPasteboard.general.changeCount
        #endif
    }

    #if os(macOS)
    /// Something outside the app wrote the system pasteboard after the last internal copy, so a
    /// paste should prefer it.
    var systemPasteboardIsNewer: Bool {
        NSPasteboard.general.changeCount != pasteboardChangeCount
    }
    #endif
}
