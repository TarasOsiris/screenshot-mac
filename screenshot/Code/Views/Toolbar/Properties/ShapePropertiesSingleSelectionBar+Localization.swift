import SwiftUI

extension ShapePropertiesSingleSelectionBar {
    // MARK: - Localization Popover

    @ViewBuilder
    func textLocalizationButton(shape: CanvasShapeModel, shapeId: UUID) -> some View {
        Button {
            isTextLocalizationPopoverPresented.toggle()
        } label: {
            Image(systemName: "globe")
                .font(.system(size: UIMetrics.ActionButton.iconSize))
                // The text specifically, not any overridden field: this button opens the translation
                // editor, so tinting it for a nudged x position promises a translation that isn't there.
                .localeOverriddenTint(.text)
                .frame(
                    width: max(UIMetrics.IconButton.frameSize, UIMetrics.ActionButton.minTouchTarget),
                    height: max(UIMetrics.IconButton.frameSize, UIMetrics.ActionButton.minTouchTarget)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Translated text is edited behind this button, so this is where its mark belongs.
        .localeOverridden(.text)
        .help("Localization")
        .accessibilityLabel("Localization")
        // Sheet, not a docked panel: a row per language with an inline text field is sheet-scale,
        // and a bottom-docked panel would put those fields under the software keyboard.
        .barPopover(isPresented: $isTextLocalizationPopoverPresented, title: "Localization", style: .sheet) {
            #if os(macOS)
            TextLocalizationControls(state: state, shapeId: shapeId, fallbackShape: shape) {
                isTextLocalizationPopoverPresented = false
            }
            #else
            TextLocalizationSheetContent(state: state, shapeId: shapeId, fallbackShape: shape)
            #endif
        }
    }
}
