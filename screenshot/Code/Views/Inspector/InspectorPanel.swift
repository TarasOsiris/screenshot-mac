import SwiftUI

/// The right-hand sidebar: the selected row's settings, or — with `includesShapes`, the macOS
/// selection inspector — the selected shapes' properties.
struct InspectorPanel: View {
    @Bindable var state: AppState
    var includesShapes = false

    var body: some View {
        let content = InspectorContent.resolve(
            row: state.selectedRow,
            selectedShapeIds: state.selectedShapeIds,
            previewingRows: state.viewMode.previewingRows,
            includesShapes: includesShapes
        )
        switch content {
        case .empty:
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
        case .shape(let shapeId):
            ShapeInspector(state: state, shapeId: shapeId)
        case .shapes:
            MultiShapeInspector(state: state)
        #endif
        default:
            RowInspector(state: state)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if includesShapes {
            ContentUnavailableView(
                "No Selection",
                systemImage: "cursorarrow.rays",
                description: Text("Select a row or a shape to edit it here.")
            )
        } else {
            ContentUnavailableView(
                "No Row Selected",
                systemImage: "rectangle.stack",
                description: Text("Select a row to edit its settings.")
            )
        }
    }
}

extension View {
    /// The three inspector panels are one surface, so they share a density. `compactControlSize`
    /// rather than `.controlSize(.small)`: the row inspector also builds on iPad, where shrinking
    /// the controls would put them under the touch-target floor.
    func inspectorFormChrome() -> some View {
        formStyle(.grouped)
            .scaledFont(UIMetrics.FontSize.body)
            .compactControlSize()
    }
}
