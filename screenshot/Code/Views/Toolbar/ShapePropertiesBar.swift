import SwiftUI
import Translation
import UniformTypeIdentifiers

struct ShapePropertiesBar: View {
    @Bindable var state: AppState

    var body: some View {
        if state.selectedShapeIds.count > 1 {
            ShapePropertiesMultiSelectionBar(state: state)
        } else {
            ShapePropertiesSingleSelectionBar(state: state)
        }
    }
}
