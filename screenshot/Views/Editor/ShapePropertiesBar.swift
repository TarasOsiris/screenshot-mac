import SwiftUI

struct ShapePropertiesBar: View {
    @Bindable var state: AppState
    @State private var isDeletingShape = false

    private var rowIndex: Int? { state.selectedRowIndex }
    private var shapeIndex: Int? {
        guard let rowIndex, let shapeId = state.selectedShapeId else { return nil }
        return state.rows[rowIndex].shapes.firstIndex { $0.id == shapeId }
    }
    private var canBringToFront: Bool {
        guard let rowIndex, let shapeIndex else { return false }
        return shapeIndex < state.rows[rowIndex].shapes.count - 1
    }
    private var canSendToBack: Bool {
        guard let shapeIndex else { return false }
        return shapeIndex > 0
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

                // Rotation
                separator

                controlGroup("Rotation") {
                    Slider(value: $state.rows[rowIndex].shapes[shapeIdx].rotation.onSet { state.scheduleSave() }, in: 0...360)
                    .frame(width: 80)

                    Text(verbatim: "\(Int(state.rows[rowIndex].shapes[shapeIdx].rotation))°")
                        .frame(width: 28, alignment: .trailing)
                }

                // Border radius (rectangle)
                if shape.type == .rectangle {
                    separator

                    controlGroup("Radius") {
                        Slider(value: $state.rows[rowIndex].shapes[shapeIdx].borderRadius.onSet { state.scheduleSave() }, in: 0...100)
                        .frame(width: 80)
                    }
                }

                // Device properties
                if shape.type == .device {
                    separator

                    controlGroup("Body") {
                        ColorPicker("", selection: $state.rows[rowIndex].shapes[shapeIdx].deviceBodyColor.onSet { state.scheduleSave() }, supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 30)
                    }

                    if shape.screenshotFileName != nil {
                        separator

                        Button {
                            state.removeScreenshot(for: shape.id)
                        } label: {
                            Label("Remove Image", systemImage: "photo.badge.minus")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
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

                // Layer order
                barButton("square.3.layers.3d.top.filled", disabled: !canBringToFront) {
                    state.bringSelectedShapeToFront()
                }
                .help("Bring to front")

                barButton("square.3.layers.3d.bottom.filled", disabled: !canSendToBack) {
                    state.sendSelectedShapeToBack()
                }
                .help("Send to back")

                // Duplicate
                barButton("doc.on.doc") {
                    state.duplicateSelectedShape()
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

    private func barButton(_ icon: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? .tertiary : .secondary)
        .disabled(disabled)
    }
}
