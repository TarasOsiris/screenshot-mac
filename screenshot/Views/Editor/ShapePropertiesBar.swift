import SwiftUI

struct ShapePropertiesBar: View {
    @Bindable var state: AppState
    @State private var isDeletingShape = false

    private var rowIndex: Int? { state.selectedRowIndex }
    private var shapeIndex: Int? {
        guard let rowIndex, let shapeId = state.selectedShapeId else { return nil }
        return state.rows[rowIndex].shapes.firstIndex { $0.id == shapeId }
    }

    var body: some View {
        if let rowIndex, let shapeIdx = shapeIndex {
            let shape = state.rows[rowIndex].shapes[shapeIdx]

            HStack(spacing: 0) {
                // Color
                ColorPicker("", selection: $state.rows[rowIndex].shapes[shapeIdx].color.onSet { state.scheduleSave() }, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 30)

                separator

                // Opacity
                controlGroup("Opacity") {
                    Slider(value: $state.rows[rowIndex].shapes[shapeIdx].opacity.onSet { state.scheduleSave() }, in: 0...1)
                    .frame(width: 80)

                    Text(verbatim: "\(Int(state.rows[rowIndex].shapes[shapeIdx].opacity * 100))%")
                        .frame(width: 32, alignment: .trailing)
                }

                // Rotation (not for circles)
                if shape.type != .circle {
                    separator

                    controlGroup("Rotation") {
                        Slider(value: $state.rows[rowIndex].shapes[shapeIdx].rotation.onSet { state.scheduleSave() }, in: 0...360)
                        .frame(width: 80)

                        Text(verbatim: "\(Int(state.rows[rowIndex].shapes[shapeIdx].rotation))°")
                            .frame(width: 28, alignment: .trailing)
                    }
                }

                // Border radius (rectangle)
                if shape.type == .rectangle {
                    separator

                    controlGroup("Radius") {
                        Slider(value: $state.rows[rowIndex].shapes[shapeIdx].borderRadius.onSet { state.scheduleSave() }, in: 0...100)
                        .frame(width: 80)
                    }
                }

                // Text properties
                if shape.type == .text {
                    separator

                    TextField("Text", text: Binding(
                        get: { state.rows[rowIndex].shapes[shapeIdx].text ?? "" },
                        set: { state.rows[rowIndex].shapes[shapeIdx].text = $0; state.scheduleSave() }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)

                    separator

                    controlGroup("Size") {
                        Slider(value: Binding(
                            get: { state.rows[rowIndex].shapes[shapeIdx].fontSize ?? 72 },
                            set: { state.rows[rowIndex].shapes[shapeIdx].fontSize = $0; state.scheduleSave() }
                        ), in: 12...200)
                        .frame(width: 70)
                    }

                    separator

                    Picker("", selection: Binding(
                        get: { state.rows[rowIndex].shapes[shapeIdx].fontWeight ?? 400 },
                        set: { state.rows[rowIndex].shapes[shapeIdx].fontWeight = $0; state.scheduleSave() }
                    )) {
                        Text("Light").tag(300)
                        Text("Regular").tag(400)
                        Text("Medium").tag(500)
                        Text("Bold").tag(700)
                    }
                    .labelsHidden()
                    .frame(width: 90)
                }

                Spacer()

                // Duplicate
                barButton("doc.on.doc") {
                    state.addShape(shape.duplicated(offsetX: 20, offsetY: 20))
                }

                // Delete
                barButton("trash") {
                    isDeletingShape = true
                }
                .foregroundStyle(.red.opacity(0.8))
            }
            .font(.system(size: 11))
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
            .alert("Delete Shape", isPresented: $isDeletingShape) {
                Button("Delete", role: .destructive) {
                    state.deleteShape(shape.id)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete this shape?")
            }
        }
    }

    private var separator: some View {
        Divider()
            .frame(height: 16)
            .padding(.horizontal, 8)
    }

    private func controlGroup<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func barButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }
}
