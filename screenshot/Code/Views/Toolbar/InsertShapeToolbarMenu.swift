#if os(macOS)
import SwiftUI

/// Toolbar Insert menu for the selection inspector, where the row inspector's Shapes grid is out
/// of reach whenever a shape is selected. Inserts into the selected row.
struct InsertShapeToolbarMenu: View {
    @Bindable var state: AppState
    @State private var isSvgDialogPresented = false

    /// Everything the Shapes submenu and the SVG dialog don't already cover.
    private static let otherTypes = ShapeType.allCases.filter { !ShapeType.shapeMenuTypes.contains($0) && $0 != .svg }

    private var targetRowId: UUID? {
        guard let rowId = state.selectedRowId, !state.viewMode.previewingRows.contains(rowId) else { return nil }
        return rowId
    }

    var body: some View {
        Menu {
            ForEach(ShapeType.shapeMenuTypes, id: \.self) { type in
                insertButton(type)
            }
            Divider()
            ForEach(Self.otherTypes, id: \.self) { type in
                insertButton(type)
            }
            Divider()
            Button(ShapeType.svg.label + "…", systemImage: ShapeType.svg.icon) {
                isSvgDialogPresented = true
            }
        } label: {
            Label("Insert", systemImage: "plus.square.on.square")
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Insert a shape into the selected row")
        .disabled(targetRowId == nil)
        .sheet(isPresented: $isSvgDialogPresented) {
            SvgPasteDialog(isPresented: $isSvgDialogPresented) { svgContent, size, useColor, color in
                guard let rowId = targetRowId else { return }
                state.insertSvgShape(content: svgContent, naturalSize: size, customColor: useColor ? color : nil, inRow: rowId)
            }
        }
    }

    private func insertButton(_ type: ShapeType) -> some View {
        Button(type.label, systemImage: type.icon) {
            guard let rowId = targetRowId else { return }
            state.insertDefaultShape(type, inRow: rowId)
        }
    }
}
#endif
