#if os(iOS)
import SwiftUI

/// The rich-text format bar that floats over the bottom of the canvas while editing text on iPad.
/// Observes the active editor's `RichTextFormatController` so its toggles reflect the live
/// selection. It sits *above* the element properties bar (not in the keyboard's accessory area),
/// with a transparent surround so the canvas shows through.
struct RichTextDockedBar: View {
    @ObservedObject var controller: RichTextFormatController

    var body: some View {
        RichTextFormatBar(
            selectionState: controller.selectionState,
            onApplyFormat: { controller.applyAction($0) }
        )
    }
}
#endif
