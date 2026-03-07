import SwiftUI
import UniformTypeIdentifiers

struct ShapePropertiesBar: View {
    @Bindable var state: AppState
    @State private var isReplacingImage = false
    @State private var isReplacingSvg = false

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
                // Color (not shown for devices or SVGs — they have their own color controls)
                if shape.type != .device && shape.type != .svg {
                    ColorPicker("", selection: $state.rows[rowIndex].shapes[shapeIdx].color.onSet { state.scheduleSave() }, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 30)

                    separator
                }

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
                            isReplacingImage = true
                        } label: {
                            Label("Replace Image", systemImage: "photo.badge.arrow.down")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .fileImporter(isPresented: $isReplacingImage, allowedContentTypes: [.image]) { result in
                            if case .success(let url) = result {
                                let didAccess = url.startAccessingSecurityScopedResource()
                                defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                                if let image = NSImage(contentsOf: url) {
                                    state.saveScreenshot(image, for: shape.id)
                                }
                            }
                        }
                    }
                }

                // SVG properties
                if shape.type == .svg {
                    separator

                    Toggle(isOn: Binding(
                        get: { state.rows[rowIndex].shapes[shapeIdx].svgUseColor ?? false },
                        set: { state.rows[rowIndex].shapes[shapeIdx].svgUseColor = $0; state.scheduleSave() }
                    )) {
                        HStack(spacing: 4) {
                            Text("Custom color")
                                .foregroundStyle(.secondary)
                            if shape.svgUseColor == true {
                                ColorPicker("", selection: $state.rows[rowIndex].shapes[shapeIdx].color.onSet { state.scheduleSave() }, supportsOpacity: false)
                                    .labelsHidden()
                                    .frame(width: 30)
                            }
                        }
                    }
                    .toggleStyle(.switch)

                    separator

                    Button {
                        isReplacingSvg = true
                    } label: {
                        Label("Replace SVG", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
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

                separator

                ControlGroup {
                    barButton("square.3.layers.3d.top.filled", disabled: !canBringToFront) {
                        state.bringSelectedShapeToFront()
                    }
                    .help("Bring to front")

                    barButton("square.3.layers.3d.bottom.filled", disabled: !canSendToBack) {
                        state.sendSelectedShapeToBack()
                    }
                    .help("Send to back")

                    barButton("doc.on.doc") {
                        state.duplicateSelectedShape()
                    }
                    .help("Duplicate")

                    barButton("trash") {
                        state.deleteShape(shape.id)
                    }
                    .foregroundStyle(.red.opacity(0.8))
                    .help("Delete")
                }
            }
            .font(.system(size: 11))
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
            .sheet(isPresented: $isReplacingSvg) {
                SvgPasteDialog(isPresented: $isReplacingSvg) { svgContent, _ in
                    state.rows[rowIndex].shapes[shapeIdx].svgContent = svgContent
                    state.scheduleSave()
                }
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
        .buttonStyle(.borderless)
        .foregroundStyle(disabled ? .tertiary : .secondary)
        .disabled(disabled)
    }
}
