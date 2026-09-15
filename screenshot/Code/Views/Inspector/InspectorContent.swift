import Foundation

/// What the inspector shows for the current selection.
enum InspectorContent: Equatable {
    case empty
    case row
    case shape(UUID)
    case shapes

    /// `includesShapes` is false wherever shape properties live in the bottom bar instead, so a
    /// shape selection keeps showing its row.
    static func resolve(
        row: ScreenshotRow?,
        selectedShapeIds: Set<UUID>,
        previewingRows: Set<UUID>,
        includesShapes: Bool
    ) -> InspectorContent {
        guard let row else { return .empty }
        guard showsShapeProperties(includesShapes: includesShapes, rowIsPreviewing: previewingRows.contains(row.id)) else {
            return .row
        }
        let present = selectedShapeIds.intersection(row.shapes.lazy.map(\.id))
        if present.count > 1 { return .shapes }
        if let shapeId = present.first { return .shape(shapeId) }
        return .row
    }

    /// A previewing row can't be edited, so its preview panel stays even with shapes selected.
    static func showsShapeProperties(includesShapes: Bool, rowIsPreviewing: Bool) -> Bool {
        includesShapes && !rowIsPreviewing
    }

    /// The bottom properties bar steps aside only while an open inspector is showing the shapes;
    /// otherwise it is the only place their properties can appear.
    static func showsPropertiesBar(hasShapeSelection: Bool, inspectorShowsShapes: Bool, inspectorPresented: Bool) -> Bool {
        hasShapeSelection && !(inspectorPresented && inspectorShowsShapes)
    }
}
