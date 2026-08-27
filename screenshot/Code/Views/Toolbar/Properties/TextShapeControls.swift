import SwiftUI

struct TextShapeControls<TextPopoverContent: View>: View {
    private let textPopoverContent: TextPopoverContent

    init(@ViewBuilder textPopoverContent: () -> TextPopoverContent) {
        self.textPopoverContent = textPopoverContent()
    }

    var body: some View {
        ShapePropertiesSection {
            textPopoverContent
        }
    }
}
