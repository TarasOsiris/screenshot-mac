import SwiftUI
import Translation
import UniformTypeIdentifiers

struct ShapePropertiesBar: View {
    private static let defaultFontSize: CGFloat = 72
    private static let fontSizeRange: ClosedRange<CGFloat> = 12...200

    @Bindable var state: AppState
    @State private var isReplacingImage = false
    @State private var isReplacingSvg = false
    @State private var translationConfig: TranslationSession.Configuration?
    @State private var isTranslating = false

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

    /// Whether a shape has a locale image override for the active locale.
    private func hasLocaleImageOverride(_ shapeId: UUID) -> Bool {
        guard !state.localeState.isBaseLocale else { return false }
        return state.localeState.override(forCode: state.localeState.activeLocaleCode, shapeId: shapeId)?.overrideImageFileName != nil
    }

    @ViewBuilder
    private func localeImageResetButton(shapeId: UUID) -> some View {
        if hasLocaleImageOverride(shapeId) {
            barButton("arrow.counterclockwise", help: "Reset to default locale image") {
                state.resetLocaleImageOverride(shapeId: shapeId)
            }
        }
    }

    var body: some View {
        if let rowIndex, let shapeIdx = shapeIndex {
            let shape = resolvedShape(at: rowIndex, shapeIdx: shapeIdx)
            let shapeId = shape.id

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    shapeBadge(shape)

                    // Device properties (frame first)
                    if shape.type == .device {
                        section {
                            devicePicker(shape: shape, shapeId: shapeId)

                            // Body color for abstract devices only
                            if shape.resolvedDeviceFrame == nil {
                                separator

                                controlGroup("Body") {
                                    HStack(spacing: 4) {
                                        ColorPicker("", selection: deviceBodyColorBinding(shapeId), supportsOpacity: false)
                                            .labelsHidden()
                                            .padding(.horizontal, 4)
                                            .help("Device body color")

                                        barButton(
                                            "arrow.counterclockwise",
                                            help: "Reset to row default device body color",
                                            disabled: !hasDeviceBodyColorOverride(shapeId)
                                        ) {
                                            resetDeviceBodyColor(shapeId)
                                        }
                                    }
                                }
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

                                localeImageResetButton(shapeId: shapeId)
                            }
                        }
                    }

                    section {
                        // Color (not shown for devices, SVGs, or images)
                        if shape.type != .device && shape.type != .svg && shape.type != .image {
                            ColorPicker("", selection: shapeBinding(shapeId, \.color), supportsOpacity: false)
                                .labelsHidden()
                                .frame(width: 30)
                                .help("Fill color")

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
                                Slider(value: shapeBinding(shapeId, \.borderRadius), in: 0...500)
                                    .frame(width: 80)

                                Text(verbatim: "\(Int(shape.borderRadius))")
                                    .frame(width: 28, alignment: .trailing)
                            }
                        }
                    }

                    // Image properties
                    if shape.type == .image {
                        section {
                            Button {
                                isReplacingImage = true
                            } label: {
                                Label(shape.imageFileName != nil ? "Replace Image" : "Choose Image", systemImage: "photo.badge.arrow.down")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)

                            localeImageResetButton(shapeId: shapeId)
                        }
                    }

                    // SVG properties
                    if shape.type == .svg {
                        section {
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
                                        .help("SVG custom color")
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
                    }

                    // Locale override indicator (any shape type)
                    if !state.localeState.isBaseLocale && hasLocaleOverride {
                        overrideIndicator(shapeId: shapeId)
                    }

                    // Text properties
                    if shape.type == .text {
                        section {
                            FontPicker(
                                selection: shapeBinding(shapeId, \.fontName, default: ""),
                                customFonts: state.customFonts,
                                onImportFont: { url in state.importCustomFont(from: url) }
                            )

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
                            .help("Text alignment")

                            Toggle(isOn: shapeBinding(shapeId, \.italic, default: false)) {
                                Image(systemName: "italic")
                            }
                            .toggleStyle(.button)
                            .help("Italic")

                            Toggle(isOn: shapeBinding(shapeId, \.uppercase, default: false)) {
                                Text("AA")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .toggleStyle(.button)
                            .help("Uppercase")
                        }

                        section {
                            controlGroup("Tracking") {
                                Slider(value: shapeBinding(shapeId, \.letterSpacing, default: 0), in: -5...30)
                                    .frame(width: 70)
                            }

                            separator

                            controlGroup("Line") {
                                Slider(value: shapeBinding(shapeId, \.lineSpacing, default: 0), in: -20...50)
                                    .frame(width: 70)
                            }

                            if !state.localeState.isBaseLocale {
                                separator

                                Button {
                                    triggerTranslation()
                                } label: {
                                    if isTranslating {
                                        ProgressView()
                                            .controlSize(.small)
                                            .frame(width: 16, height: 16)
                                    } else {
                                        Label("Translate", systemImage: "globe")
                                    }
                                }
                                .buttonStyle(.borderless)
                                .disabled(isTranslating || (state.rows[rowIndex].shapes[shapeIdx].text ?? "").isEmpty)
                                .help("Translate from base locale")
                            }
                        }
                    }

                    section {
                        Toggle(isOn: shapeBinding(shapeId, \.clipToTemplate, default: false)) {
                            Label("Clip", systemImage: "rectangle.on.rectangle.slash")
                        }
                        .toggleStyle(.button)
                        .help("Clip to screenshot")
                    }

                    section {
                        HStack(spacing: 4) {
                            barButton("square.3.layers.3d.top.filled", help: "Bring to front (⇧⌘])", disabled: !canBringToFront) {
                                state.bringSelectedShapeToFront()
                            }

                            barButton("square.3.layers.3d.bottom.filled", help: "Send to back (⇧⌘[)", disabled: !canSendToBack) {
                                state.sendSelectedShapeToBack()
                            }

                            barButton("doc.on.doc", help: "Duplicate (⌘D)") {
                                state.duplicateSelectedShape()
                            }

                            barButton("trash", help: "Delete (⌫)", isDestructive: true) {
                                state.deleteShape(shapeId)
                            }
                        }
                    }

                    Button {
                        state.selectedShapeId = nil
                    } label: {
                        Label("Done", systemImage: "checkmark")
                    }
                    .buttonStyle(.bordered)
                    .help("Deselect shape (Esc)")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .font(.system(size: 11))
            .controlSize(.small)
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
            .translationTask(translationConfig) { session in
                guard let ri = state.selectedRowIndex,
                      let shapeId = state.selectedShapeId,
                      let si = state.rows[ri].shapes.firstIndex(where: { $0.id == shapeId })
                else { return }
                let baseShape = state.rows[ri].shapes[si]
                guard baseShape.type == .text, let baseText = baseShape.text, !baseText.isEmpty else { return }
                isTranslating = true
                defer { isTranslating = false }
                do {
                    let response = try await session.translate(baseText)
                    state.updateTranslationText(shapeId: baseShape.id, text: response.targetText)
                } catch {
                    print("Translation failed: \(error)")
                }
            }
        }
    }

    private func triggerTranslation() {
        translationConfig.refresh(
            source: state.localeState.baseLocaleCode,
            target: state.localeState.activeLocaleCode
        )
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

    // MARK: - Device Picker

    /// Unified device picker: abstract devices first, separator, then real frames grouped by model with submenus.
    @ViewBuilder
    private func devicePicker(shape: CanvasShapeModel, shapeId: UUID) -> some View {
        Menu {
            DeviceMenuContent(
                onSelectCategory: { cat in
                    selectAbstractDevice(shapeId: shapeId, category: cat)
                },
                onSelectFrame: { frame in
                    selectRealFrame(shapeId: shapeId, frame: frame)
                }
            )
        } label: {
            HStack(spacing: 6) {
                Image(systemName: devicePickerIcon(shape: shape))
                Text(devicePickerLabel(shape: shape))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
        .frame(width: 260, alignment: .leading)
        .help(devicePickerHelp(shape: shape))
    }

    private func devicePickerLabel(shape: CanvasShapeModel) -> String {
        if let frameId = shape.deviceFrameId, let frame = DeviceFrameCatalog.frame(for: frameId) {
            return "\(frame.modelName) - \(frame.shortLabel)"
        }
        return (shape.deviceCategory ?? .iphone).label
    }

    private func devicePickerIcon(shape: CanvasShapeModel) -> String {
        if let frameId = shape.deviceFrameId, let frame = DeviceFrameCatalog.frame(for: frameId) {
            return frame.icon
        }
        return (shape.deviceCategory ?? .iphone).icon
    }

    private func devicePickerHelp(shape: CanvasShapeModel) -> String {
        if let frameId = shape.deviceFrameId, let frame = DeviceFrameCatalog.frame(for: frameId) {
            return "Current device frame: \(frame.label)"
        }
        return "Current abstract device: \((shape.deviceCategory ?? .iphone).label)"
    }

    private func selectAbstractDevice(shapeId: UUID, category: DeviceCategory) {
        guard let i = idx(for: shapeId) else { return }
        var resolved = resolvedShape(at: i.row, shapeIdx: i.shape)
        resolved.deviceFrameId = nil
        resolved.deviceCategory = category
        resolved.adjustToDeviceAspectRatio()
        state.updateShape(resolved)
    }

    private func selectRealFrame(shapeId: UUID, frame: DeviceFrame) {
        guard let i = idx(for: shapeId) else { return }
        var resolved = resolvedShape(at: i.row, shapeIdx: i.shape)
        resolved.deviceCategory = frame.fallbackCategory
        resolved.deviceFrameId = frame.id
        resolved.adjustToDeviceAspectRatio()
        state.updateShape(resolved)
    }

    private func deviceBodyColorBinding(_ shapeId: UUID) -> Binding<Color> {
        Binding(
            get: {
                guard let i = idx(for: shapeId) else { return CanvasShapeModel.defaultDeviceBodyColor }
                let shape = resolvedShape(at: i.row, shapeIdx: i.shape)
                return shape.deviceBodyColorData?.color ?? state.rows[i.row].defaultDeviceBodyColor
            },
            set: { newValue in
                guard let i = idx(for: shapeId) else { return }
                var resolved = resolvedShape(at: i.row, shapeIdx: i.shape)
                resolved.deviceBodyColorData = CodableColor(newValue)
                state.updateShape(resolved)
            }
        )
    }

    private func hasDeviceBodyColorOverride(_ shapeId: UUID) -> Bool {
        guard let i = idx(for: shapeId) else { return false }
        return state.rows[i.row].shapes[i.shape].deviceBodyColorData != nil
    }

    private func resetDeviceBodyColor(_ shapeId: UUID) {
        guard let i = idx(for: shapeId) else { return }
        guard state.rows[i.row].shapes[i.shape].type == .device else { return }
        var resolved = resolvedShape(at: i.row, shapeIdx: i.shape)
        resolved.deviceBodyColorData = nil
        state.updateShape(resolved)
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

    private func section<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 6) {
            content()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.separator.opacity(0.35), lineWidth: 0.5)
        )
    }

    private func shapeBadge(_ shape: CanvasShapeModel) -> some View {
        HStack(spacing: 6) {
            Image(systemName: shape.type.icon)
                .font(.system(size: 11, weight: .medium))
            Text(shape.type.label)
                .font(.system(size: 11, weight: .semibold))
            Text(verbatim: "\(Int(shape.width))×\(Int(shape.height))")
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.accentColor.opacity(0.14))
        )
    }

    private func overrideIndicator(shapeId: UUID) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 5, height: 5)
            Text("Overridden")
                .font(.system(size: 10))
                .foregroundStyle(Color.accentColor)

            barButton("arrow.counterclockwise", help: "Reset locale override") {
                state.resetLocaleOverride(shapeId: shapeId)
            }
        }
    }

    private func barButton(
        _ icon: String,
        help: String,
        isDestructive: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .focusable(false)
        .foregroundStyle(
            disabled
            ? AnyShapeStyle(.tertiary)
            : (isDestructive ? AnyShapeStyle(Color.red.opacity(0.8)) : AnyShapeStyle(.secondary))
        )
        .disabled(disabled)
        .help(help)
    }
}
