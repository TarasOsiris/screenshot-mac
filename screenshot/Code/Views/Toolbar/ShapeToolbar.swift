import SwiftUI

struct ShapeToolbar: View {
    @Bindable var state: AppState
    @State private var isSvgDialogPresented = false

    private static let nonMenuTypes = ShapeType.allCases.filter { !ShapeType.shapeMenuTypes.contains($0) }

    /// Touch targets need more room on iPad; macOS keeps the compact inspector density.
    private var buttonControlSize: ControlSize {
        #if os(macOS)
        .small
        #else
        .large
        #endif
    }

    private var gridSpacing: CGFloat {
        #if os(macOS)
        6
        #else
        10
        #endif
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: 2), spacing: gridSpacing) {
            shapesMenu
            ForEach(Self.nonMenuTypes, id: \.self) { type in
                shapeButton(type) {
                    if type == .svg {
                        isSvgDialogPresented = true
                    } else {
                        addShape(type)
                    }
                }
            }
        }
        // Container-level so every cell truncates instead of wrapping when the
        // inspector gets narrow (presented popovers are unaffected).
        .lineLimit(1)
        .sheet(isPresented: $isSvgDialogPresented) {
            SvgPasteDialog(isPresented: $isSvgDialogPresented) { svgContent, size, useColor, color in
                addSvgShape(svgContent: svgContent, size: size, useColor: useColor, color: color)
            }
        }
    }

    #if os(macOS)
    @State private var isShapesMenuPresented = false

    // Plain button + popover (not Menu) so the chrome matches the sibling buttons —
    // .menuStyle(.button) adds extra horizontal padding and a chevron on macOS.
    private var shapesMenu: some View {
        Button {
            isShapesMenuPresented = true
        } label: {
            Label("Shapes", systemImage: "square.on.circle")
                .labelStyle(.titleAndIcon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .controlSize(buttonControlSize)
        .help("Add shape")
        .popover(isPresented: $isShapesMenuPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(ShapeType.shapeMenuTypes, id: \.self) { type in
                    Button {
                        isShapesMenuPresented = false
                        addShape(type)
                    } label: {
                        Label(type.label, systemImage: type.icon)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .frame(minWidth: 140)
        }
    }
    #else
    private var shapesMenu: some View {
        Menu {
            ForEach(ShapeType.shapeMenuTypes, id: \.self) { type in
                Button {
                    addShape(type)
                } label: {
                    Label(type.label, systemImage: type.icon)
                }
            }
        } label: {
            Label("Shapes", systemImage: "square.on.circle")
                .labelStyle(.titleAndIcon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(buttonControlSize)
        .help("Add shape")
    }
    #endif

    private func shapeButton(_ type: ShapeType, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(type.label, systemImage: type.icon)
                .labelStyle(.titleAndIcon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .controlSize(buttonControlSize)
        .help("Add \(type.label)")
    }

    private func addShape(_ type: ShapeType) {
        guard let rowId = state.selectedRowId else { return }
        state.insertDefaultShape(type, inRow: rowId)
    }

    private func addSvgShape(svgContent: String, size: CGSize, useColor: Bool, color: Color) {
        guard let rowId = state.selectedRowId else { return }
        state.insertSvgShape(content: svgContent, naturalSize: size, customColor: useColor ? color : nil, inRow: rowId)
    }
}
