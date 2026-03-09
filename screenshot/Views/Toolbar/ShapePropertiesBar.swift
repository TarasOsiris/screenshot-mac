import SwiftUI
import UniformTypeIdentifiers

struct ShapePropertiesBar: View {
    private static let defaultFontSize: CGFloat = 72
    private static let fontSizeRange: ClosedRange<CGFloat> = 12...200

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

    /// Safely resolve current index for a shape by ID; returns nil if shape or row disappeared.
    private func idx(for shapeId: UUID) -> (row: Int, shape: Int)? {
        guard let ri = rowIndex, ri < state.rows.count,
              let si = state.rows[ri].shapes.firstIndex(where: { $0.id == shapeId })
        else { return nil }
        return (ri, si)
    }

    /// The selected shape with locale overrides applied (for display).
    private func resolvedShape(at rowIndex: Int, shapeIdx: Int) -> CanvasShapeModel {
        let base = state.rows[rowIndex].shapes[shapeIdx]
        return LocaleService.resolveShape(base, localeState: state.localeState)
    }

    /// Whether the selected shape has any locale override for the active locale.
    private var hasLocaleOverride: Bool {
        guard let shapeId = state.selectedShapeId, !state.localeState.isBaseLocale else { return false }
        return state.localeState.hasOverride(shapeId: shapeId)
    }

    var body: some View {
        if let rowIndex, let shapeIdx = shapeIndex {
            let shape = resolvedShape(at: rowIndex, shapeIdx: shapeIdx)
            let shapeId = shape.id

            WrappingHStack(spacing: 6, lineSpacing: 6) {
                // Color (not shown for devices, SVGs, or images)
                if shape.type != .device && shape.type != .svg && shape.type != .image {
                    ColorPicker("", selection: shapeBinding(shapeId, \.color), supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 30)

                    separator
                }

                // Opacity
                controlGroup("Opacity") {
                    Slider(value: shapeBinding(shapeId, \.opacity), in: 0...1)
                    .frame(width: 80)

                    Text(verbatim: "\(Int((idx(for: shapeId).map { state.rows[$0.row].shapes[$0.shape].opacity } ?? 1) * 100))%")
                        .frame(width: 32, alignment: .trailing)
                }

                // Rotation
                separator

                controlGroup("Rotation") {
                    Slider(value: shapeBinding(shapeId, \.rotation), in: 0...360)
                    .frame(width: 80)

                    Text(verbatim: "\(Int(idx(for: shapeId).map { state.rows[$0.row].shapes[$0.shape].rotation } ?? 0))°")
                        .frame(width: 28, alignment: .trailing)
                }

                // Border radius (rectangle or image)
                if shape.type == .rectangle || shape.type == .image {
                    separator

                    controlGroup("Radius") {
                        Slider(value: shapeBinding(shapeId, \.borderRadius), in: 0...100)
                        .frame(width: 80)
                    }
                }

                // Device properties
                if shape.type == .device {
                    separator

                    controlGroup("Body") {
                        ColorPicker("", selection: shapeBinding(shapeId, \.deviceBodyColor), supportsOpacity: false)
                            .labelsHidden()
                            .padding(.horizontal, 4)
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
                    }
                }

                // Image properties
                if shape.type == .image {
                    separator

                    Button {
                        isReplacingImage = true
                    } label: {
                        Label(shape.imageFileName != nil ? "Replace Image" : "Choose Image", systemImage: "photo.badge.arrow.down")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }

                // SVG properties
                if shape.type == .svg {
                    separator

                    HStack(spacing: 4) {
                        Toggle(isOn: shapeBinding(shapeId, \.svgUseColor, default: false)) {
                            Text("Custom color")
                                .foregroundStyle(.secondary)
                        }
                        .toggleStyle(.switch)

                        if shape.svgUseColor == true {
                            ColorPicker("", selection: shapeBinding(shapeId, \.color), supportsOpacity: false)
                                .labelsHidden()
                                .frame(width: 30)
                        }
                    }

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
                    // Override indicator for non-base locale
                    if !state.localeState.isBaseLocale && hasLocaleOverride {
                        overrideIndicator(shapeId: shapeId)
                    }

                    separator

                    FontPicker(selection: shapeBinding(shapeId, \.fontName, default: ""))

                    separator

                    controlGroup("Size") {
                        Slider(value: shapeBinding(shapeId, \.fontSize, default: Self.defaultFontSize), in: Self.fontSizeRange)
                            .frame(width: 70)
                        TextField("", value: Binding(
                            get: {
                                guard let i = idx(for: shapeId) else { return Int(Self.defaultFontSize) }
                                return Int(resolvedShape(at: i.row, shapeIdx: i.shape).fontSize ?? Self.defaultFontSize)
                            },
                            set: { newValue in
                                let clamped = min(max(CGFloat(newValue), Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound)
                                guard let i = idx(for: shapeId) else { return }
                                var resolved = resolvedShape(at: i.row, shapeIdx: i.shape)
                                resolved.fontSize = clamped
                                state.updateShape(resolved)
                            }
                        ), format: .number)
                        .frame(width: 40)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                    }

                    separator

                    Picker("", selection: shapeBinding(shapeId, \.fontWeight, default: 400)) {
                        Text("Light").tag(300)
                        Text("Regular").tag(400)
                        Text("Medium").tag(500)
                        Text("Bold").tag(700)
                    }
                    .labelsHidden()
                    .frame(width: 90)

                    Picker("", selection: shapeBinding(shapeId, \.textAlign, default: .center)) {
                        Image(systemName: "text.alignleft").tag(TextAlign.left)
                        Image(systemName: "text.aligncenter").tag(TextAlign.center)
                        Image(systemName: "text.alignright").tag(TextAlign.right)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 90)

                    Toggle(isOn: shapeBinding(shapeId, \.italic, default: false)) {
                        Image(systemName: "italic")
                    }
                    .toggleStyle(.button)
                    .help("Italic")

                    separator

                    controlGroup("Tracking") {
                        Slider(value: shapeBinding(shapeId, \.letterSpacing, default: 0), in: -5...30)
                            .frame(width: 70)
                    }

                    separator

                    controlGroup("Line") {
                        Slider(value: shapeBinding(shapeId, \.lineSpacing, default: 0), in: 0...50)
                            .frame(width: 70)
                    }
                }

                Spacer()

                separator

                HStack(spacing: 4) {
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
                        state.deleteShape(shapeId)
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
            .fileImporter(isPresented: $isReplacingImage, allowedContentTypes: [.image]) { result in
                if case .success(let url) = result,
                   let image = NSImage.fromSecurityScopedURL(url) {
                    state.saveImage(image, for: shapeId)
                }
            }
            .sheet(isPresented: $isReplacingSvg) {
                SvgPasteDialog(isPresented: $isReplacingSvg) { svgContent, _ in
                    guard let i = idx(for: shapeId) else { return }
                    state.rows[i.row].shapes[i.shape].svgContent = svgContent
                    state.scheduleSave()
                }
            }
        }
    }

    /// Creates a Binding that always resolves the shape index by ID at access time.
    /// Reads the resolved (locale-aware) value; writes go through `updateShape` which handles locale splitting.
    private func shapeBinding<T>(_ shapeId: UUID, _ keyPath: WritableKeyPath<CanvasShapeModel, T>) -> Binding<T> where T: Sendable {
        Binding(
            get: {
                guard let i = idx(for: shapeId) else {
                    return CanvasShapeModel.placeholder[keyPath: keyPath]
                }
                return resolvedShape(at: i.row, shapeIdx: i.shape)[keyPath: keyPath]
            },
            set: { newValue in
                guard let i = idx(for: shapeId) else { return }
                var resolved = resolvedShape(at: i.row, shapeIdx: i.shape)
                resolved[keyPath: keyPath] = newValue
                state.updateShape(resolved)
            }
        )
    }

    /// Overload for optional properties with a default value.
    private func shapeBinding<T>(_ shapeId: UUID, _ keyPath: WritableKeyPath<CanvasShapeModel, T?>, default defaultValue: T) -> Binding<T> where T: Sendable {
        Binding(
            get: {
                guard let i = idx(for: shapeId) else { return defaultValue }
                return resolvedShape(at: i.row, shapeIdx: i.shape)[keyPath: keyPath] ?? defaultValue
            },
            set: { newValue in
                guard let i = idx(for: shapeId) else { return }
                var resolved = resolvedShape(at: i.row, shapeIdx: i.shape)
                resolved[keyPath: keyPath] = newValue
                state.updateShape(resolved)
            }
        )
    }

    private var separator: some View {
        Rectangle()
            .fill(.separator)
            .frame(width: 1, height: 18)
            .padding(.horizontal, 4)
    }

    private func controlGroup<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func overrideIndicator(shapeId: UUID) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 5, height: 5)
            Text("Overridden")
                .font(.system(size: 10))
                .foregroundStyle(Color.accentColor)
            Button {
                state.resetLocaleOverride(shapeId: shapeId)
            } label: {
                Text("Reset")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.accentColor.opacity(0.8))
            }
            .buttonStyle(.borderless)
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
        .focusable(false)
        .foregroundStyle(disabled ? .tertiary : .secondary)
        .disabled(disabled)
    }
}
