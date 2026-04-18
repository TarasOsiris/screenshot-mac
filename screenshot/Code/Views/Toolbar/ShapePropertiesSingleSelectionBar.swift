import SwiftUI
import UniformTypeIdentifiers

struct ShapePropertiesSingleSelectionBar: View {
    private static let defaultFontSize: CGFloat = CanvasShapeModel.defaultFontSize
    private static let fontSizeRange: ClosedRange<CGFloat> = 8...400
    private static let fontSizePresets: [Int] = CanvasShapeModel.fontSizePresets
    @Bindable var state: AppState
    @State private var isReplacingSvg = false
    @State private var isReplacingFillImage = false
    @State private var isFillPopoverPresented = false
    @State private var isTextPopoverPresented = false
    @State private var editingFontSize: String = ""
    @State private var isFontSizeFieldActive = false
    @State private var editingLineHeight: String = ""
    @State private var isLineHeightFieldActive = false
    @State private var editingOpacity: String = ""
    @State private var isOpacityFieldActive = false
    @FocusState private var focusedField: Field?
    private enum Field: Hashable { case opacity, fontSize, lineHeight }
    private static let lineHeightPresets: [Int] = [50, 60, 70, 80, 90, 100, 110, 120, 130, 140, 150, 175, 200]

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

    private func pickAndReplaceImage(for shapeId: UUID) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let image = NSImage.fromSecurityScopedURL(url) else { return }
        state.saveImage(image, for: shapeId)
    }

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

    var body: some View {
        if let rowIndex, let shapeIdx = shapeIndex {
            let shape = resolvedShape(at: rowIndex, shapeIdx: shapeIdx)
            let shapeId = shape.id

            HStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ShapePropertiesBadge(shape: shape)

                        if shape.type == .device {
                            DeviceShapeControls(
                                shape: shape,
                                showsLocaleImageReset: hasLocaleImageOverride(shapeId),
                                onPickImage: { pickAndReplaceImage(for: shapeId) },
                                onResetLocaleImage: { state.resetLocaleImageOverride(shapeId: shapeId) }
                            ) {
                                devicePicker(shape: shape, shapeId: shapeId)
                            }
                        }

                        if shape.supportsDeviceModelRotation {
                            ShapeDeviceModelRotationControls(
                                shape: shape,
                                pitch: deviceModelRotationBinding(shapeId, \.devicePitch, defaultValue: \.resolvedDevicePitch),
                                yaw: deviceModelRotationBinding(shapeId, \.deviceYaw, defaultValue: \.resolvedDeviceYaw),
                                canReset: hasDeviceModelRotationOverride(shapeId),
                                onReset: { resetDeviceModelRotation(shapeId) }
                            )
                        }

                        ShapePropertiesSection {
                            if shape.type.supportsFill {
                                ShapeFillSwatchButton(
                                    shape: shape,
                                    isPresented: $isFillPopoverPresented,
                                    backgroundStyle: fillStyleBinding(shapeId),
                                    bgColor: shapeBinding(shapeId, \.color),
                                    gradientConfig: shapeBinding(shapeId, \.fillGradientConfig, default: GradientConfig()),
                                    backgroundImageConfig: shapeBinding(shapeId, \.fillImageConfig, default: BackgroundImageConfig()),
                                    backgroundImage: (idx(for: shapeId).flatMap { i in
                                        state.rows[i.row].shapes[i.shape].fillImageConfig?.fileName
                                    }).flatMap { state.screenshotImages[$0] },
                                    onChanged: { state.scheduleSave() },
                                    onPickImage: { isReplacingFillImage = true },
                                    onRemoveImage: { state.removeShapeFillImage(for: shapeId) },
                                    onDropImage: { image in state.saveShapeFillImage(image, for: shapeId) }
                                )
                                ShapePropertiesSeparator()
                            } else if shape.type != .device && shape.type != .svg && shape.type != .image {
                                ColorPicker("", selection: shapeBinding(shapeId, \.color), supportsOpacity: false)
                                    .labelsHidden()
                                    .frame(width: 30)
                                    .help("Fill color")
                                ShapePropertiesSeparator()
                            }

                            ShapePropertiesControlGroup("Opacity") {
                                HStack(spacing: 0) {
                                    TextField("", text: $editingOpacity, onEditingChanged: { editing in
                                        if editing {
                                            isOpacityFieldActive = true
                                        } else {
                                            commitOpacity(shapeId: shapeId)
                                        }
                                    })
                                    .focused($focusedField, equals: .opacity)
                                    .frame(width: 40)
                                    .textFieldStyle(.roundedBorder)
                                    .multilineTextAlignment(.center)
                                    .onAppear {
                                        editingOpacity = currentOpacityString(for: shapeId)
                                    }
                                    .onChange(of: shapeId) {
                                        isOpacityFieldActive = false
                                        focusedField = nil
                                        editingOpacity = currentOpacityString(for: shapeId)
                                    }
                                    .onChange(of: shape.opacity) {
                                        guard !isOpacityFieldActive else { return }
                                        editingOpacity = currentOpacityString(for: shapeId)
                                    }
                                    .onSubmit {
                                        commitOpacity(shapeId: shapeId)
                                    }

                                    Text("%")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                            }

                            ShapePropertiesSeparator()

                            ShapePropertiesControlGroup("Rotation") {
                                Slider(value: shapeBinding(shapeId, \.rotation, continuous: true), in: 0...360)
                                    .frame(width: 80)

                                Text(verbatim: "\(Int(idx(for: shapeId).map { state.rows[$0.row].shapes[$0.shape].rotation } ?? 0))°")
                                    .frame(width: 28, alignment: .trailing)
                            }

                            if shape.type == .rectangle || shape.type == .image || (shape.type == .device && shape.deviceCategory == .invisible) {
                                ShapePropertiesSeparator()

                                ShapePropertiesControlGroup("Radius") {
                                    Slider(value: shapeBinding(shapeId, \.borderRadius, continuous: true), in: 0...500)
                                        .frame(width: 80)

                                    Text(verbatim: "\(Int(shape.borderRadius))")
                                        .frame(width: 28, alignment: .trailing)
                                }
                            }
                        }

                        if shape.type.supportsOutline || (shape.type == .device && shape.deviceCategory == .invisible) {
                            ShapePropertiesSection {
                                ShapeOutlineControls(
                                    shape: shape,
                                    hasOutline: Binding(
                                        get: { (shape.outlineWidth ?? 0) > 0 },
                                        set: { enabled in
                                            var updated = shape
                                            updated.outlineColor = enabled ? CanvasShapeModel.defaultOutlineColor : nil
                                            updated.outlineWidth = enabled ? CanvasShapeModel.defaultOutlineWidth : nil
                                            state.updateShape(updated)
                                        }
                                    ),
                                    outlineColor: shapeBinding(shapeId, \.outlineColor, default: CanvasShapeModel.defaultOutlineColor),
                                    outlineWidth: shapeBinding(shapeId, \.outlineWidth, default: CanvasShapeModel.defaultOutlineWidth, continuous: true)
                                )
                            }
                        }

                        if shape.type == .star {
                            ShapePropertiesSection {
                                ShapePropertiesControlGroup("Points") {
                                    Stepper(
                                        value: shapeBinding(shapeId, \.starPointCount, default: CanvasShapeModel.defaultStarPointCount),
                                        in: 3...20
                                    ) {
                                        Text(verbatim: "\(shape.starPointCount ?? CanvasShapeModel.defaultStarPointCount)")
                                            .frame(width: 20, alignment: .trailing)
                                    }
                                }
                            }
                        }

                        if shape.type == .image {
                            ImageShapeControls(
                                buttonTitle: shape.imageFileName != nil ? "Replace Image" : "Choose Image",
                                showsLocaleImageReset: hasLocaleImageOverride(shapeId),
                                onPickImage: { pickAndReplaceImage(for: shapeId) },
                                onResetLocaleImage: { state.resetLocaleImageOverride(shapeId: shapeId) }
                            )
                        }

                        if shape.type == .svg {
                            SVGShapeControls(
                                usesCustomColor: shapeBinding(shapeId, \.svgUseColor, default: false),
                                color: shapeBinding(shapeId, \.color),
                                onReplace: { isReplacingSvg = true }
                            )
                        }

                        if !state.localeState.isBaseLocale && hasLocaleOverride {
                            LocaleOverrideIndicator {
                                state.resetLocaleOverride(shapeId: shapeId)
                            }
                        }

                        if shape.type == .text {
                            TextShapeControls {
                                textPopoverButton(shape: shape, shapeId: shapeId)
                            }
                        }

                        ShapePropertiesSection {
                            Toggle("Clip to Frame", isOn: shapeBinding(shapeId, \.clipToTemplate, default: false))
                                .toggleStyle(.switch)
                                .controlSize(.small)
                        }

                        ShapeSelectionActionsSection(
                            canBringToFront: canBringToFront,
                            canSendToBack: canSendToBack,
                            onBringToFront: { state.bringSelectedShapesToFront() },
                            onSendToBack: { state.sendSelectedShapesToBack() },
                            onDuplicate: { state.duplicateSelectedShapes() },
                            onDelete: { state.deleteShape(shapeId) }
                        )
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }

                Spacer(minLength: 0)

                ActionButton(icon: "xmark", tooltip: "Deselect shape (Esc)", frameSize: 24) {
                    state.selectedShapeIds = []
                }
                .padding(.trailing, 8)
            }
            .font(.system(size: 11))
            .controlSize(.small)
            .background(.bar)
            .fileImporter(isPresented: $isReplacingFillImage, allowedContentTypes: [.image]) { result in
                if case .success(let url) = result,
                   let image = NSImage.fromSecurityScopedURL(url) {
                    state.saveShapeFillImage(image, for: shapeId)
                }
            }
            .sheet(isPresented: $isReplacingSvg) {
                SvgPasteDialog(isPresented: $isReplacingSvg) { svgContent, _, useColor, color in
                    guard let i = idx(for: shapeId) else { return }
                    state.rows[i.row].shapes[i.shape].svgContent = svgContent
                    if useColor {
                        state.rows[i.row].shapes[i.shape].svgUseColor = true
                        state.rows[i.row].shapes[i.shape].color = color
                    }
                    state.scheduleSave()
                }
            }
        }
    }

    private func currentFontSizeString(for shapeId: UUID) -> String {
        guard let i = idx(for: shapeId) else { return "\(Int(Self.defaultFontSize))" }
        return "\(Int(resolvedShape(at: i.row, shapeIdx: i.shape).fontSize ?? Self.defaultFontSize))"
    }

    private func clampedFontSize(_ value: Int) -> CGFloat {
        min(max(CGFloat(value), Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound)
    }

    private func commitFontSize(shapeId: UUID) {
        isFontSizeFieldActive = false
        guard let i = idx(for: shapeId) else { return }
        guard let value = Int(editingFontSize) else {
            editingFontSize = currentFontSizeString(for: shapeId)
            return
        }
        let clamped = clampedFontSize(value)
        var resolved = resolvedShape(at: i.row, shapeIdx: i.shape)
        resolved.fontSize = clamped
        syncRichTextIfNeeded(in: &resolved, property: .fontSize)
        state.updateShape(resolved)
        editingFontSize = "\(Int(clamped))"
    }

    private func currentOpacityString(for shapeId: UUID) -> String {
        guard let i = idx(for: shapeId) else { return "100" }
        return "\(Int((state.rows[i.row].shapes[i.shape].opacity * 100).rounded()))"
    }

    private func commitOpacity(shapeId: UUID) {
        isOpacityFieldActive = false
        guard let i = idx(for: shapeId) else { return }
        guard let value = Int(editingOpacity) else {
            editingOpacity = currentOpacityString(for: shapeId)
            return
        }
        let clamped = min(max(value, 0), 100)
        var resolved = resolvedShape(at: i.row, shapeIdx: i.shape)
        resolved.opacity = Double(clamped) / 100.0
        state.updateShape(resolved)
        editingOpacity = "\(clamped)"
    }

    private func currentLineHeightString(for shapeId: UUID) -> String {
        guard let i = idx(for: shapeId) else { return "\(Int(TextLayoutStyle.defaultLineHeightMultiple * 100))" }
        let shape = resolvedShape(at: i.row, shapeIdx: i.shape)
        let font = NSFont.systemFont(
            ofSize: shape.fontSize ?? Self.defaultFontSize,
            weight: nsFontWeight(shape.fontWeight ?? 400)
        )
        let multiple = TextLayoutStyle.effectiveLineHeightMultiple(
            lineHeightMultiple: shape.lineHeightMultiple,
            legacyLineSpacing: shape.lineSpacing,
            font: font
        )
        return "\(Int((multiple * 100).rounded()))"
    }

    private func commitLineHeight(shapeId: UUID) {
        isLineHeightFieldActive = false
        guard let i = idx(for: shapeId) else { return }
        guard let value = Int(editingLineHeight) else {
            editingLineHeight = currentLineHeightString(for: shapeId)
            return
        }
        let clamped = TextLayoutStyle.clampLineHeightMultiple(CGFloat(value) / 100.0)
        var resolved = resolvedShape(at: i.row, shapeIdx: i.shape)
        resolved.lineHeightMultiple = clamped
        resolved.lineSpacing = nil
        syncRichTextIfNeeded(in: &resolved, property: .lineHeight)
        state.updateShape(resolved)
        editingLineHeight = "\(Int((clamped * 100).rounded()))"
    }

    private func syncRichTextIfNeeded(in shape: inout CanvasShapeModel, property: RichTextUtils.ShapeStyleProperty?) {
        guard shape.type == .text, let property else { return }
        RichTextUtils.syncShapeStyle(in: &shape, property: property)
    }

    private func richTextStyleProperty<T>(for keyPath: WritableKeyPath<CanvasShapeModel, T>) -> RichTextUtils.ShapeStyleProperty? {
        let anyKeyPath = keyPath as AnyKeyPath
        if anyKeyPath == \CanvasShapeModel.color { return .color }
        return nil
    }

    private func richTextStyleProperty<T>(for keyPath: WritableKeyPath<CanvasShapeModel, T?>) -> RichTextUtils.ShapeStyleProperty? {
        let anyKeyPath = keyPath as AnyKeyPath
        if anyKeyPath == \CanvasShapeModel.fontName { return .fontName }
        if anyKeyPath == \CanvasShapeModel.fontWeight { return .fontWeight }
        if anyKeyPath == \CanvasShapeModel.textAlign { return .alignment }
        if anyKeyPath == \CanvasShapeModel.italic { return .italic }
        if anyKeyPath == \CanvasShapeModel.letterSpacing { return .letterSpacing }
        return nil
    }

    /// Creates a Binding that always resolves the shape index by ID at access time.
    /// Reads the resolved (locale-aware) value; writes go through `updateShape` which handles locale splitting.
    private func shapeBinding<T>(_ shapeId: UUID, _ keyPath: WritableKeyPath<CanvasShapeModel, T>, continuous: Bool = false) -> Binding<T> where T: Sendable {
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
                syncRichTextIfNeeded(in: &resolved, property: richTextStyleProperty(for: keyPath))
                if continuous {
                    state.updateShapeContinuous(resolved)
                } else {
                    state.updateShape(resolved)
                }
            }
        )
    }

    /// Overload for optional properties with a default value.
    private func shapeBinding<T>(_ shapeId: UUID, _ keyPath: WritableKeyPath<CanvasShapeModel, T?>, default defaultValue: T, continuous: Bool = false) -> Binding<T> where T: Sendable {
        Binding(
            get: {
                guard let i = idx(for: shapeId) else { return defaultValue }
                return resolvedShape(at: i.row, shapeIdx: i.shape)[keyPath: keyPath] ?? defaultValue
            },
            set: { newValue in
                guard let i = idx(for: shapeId) else { return }
                var resolved = resolvedShape(at: i.row, shapeIdx: i.shape)
                resolved[keyPath: keyPath] = newValue
                syncRichTextIfNeeded(in: &resolved, property: richTextStyleProperty(for: keyPath))
                if continuous {
                    state.updateShapeContinuous(resolved)
                } else {
                    state.updateShape(resolved)
                }
            }
        )
    }

    private func lineHeightBinding(_ shapeId: UUID) -> Binding<CGFloat> {
        Binding(
            get: {
                guard let i = idx(for: shapeId) else {
                    return TextLayoutStyle.defaultLineHeightMultiple
                }
                let shape = resolvedShape(at: i.row, shapeIdx: i.shape)
                let font = NSFont.systemFont(
                    ofSize: shape.fontSize ?? Self.defaultFontSize,
                    weight: nsFontWeight(shape.fontWeight ?? 400)
                )
                return TextLayoutStyle.effectiveLineHeightMultiple(
                    lineHeightMultiple: shape.lineHeightMultiple,
                    legacyLineSpacing: shape.lineSpacing,
                    font: font
                )
            },
            set: { newValue in
                guard let i = idx(for: shapeId) else { return }
                var resolved = resolvedShape(at: i.row, shapeIdx: i.shape)
                resolved.lineHeightMultiple = TextLayoutStyle.clampLineHeightMultiple(newValue)
                resolved.lineSpacing = nil
                syncRichTextIfNeeded(in: &resolved, property: .lineHeight)
                state.updateShape(resolved)
            }
        )
    }

    private func nsFontWeight(_ weight: Int) -> NSFont.Weight {
        switch weight {
        case ...299: .thin
        case 300...399: .light
        case 400...499: .regular
        case 500...599: .medium
        case 600...699: .semibold
        case 700...799: .bold
        default: .heavy
        }
    }

    // MARK: - Device Picker

    /// Shared device picker used across toolbar/settings/inspector.
    @ViewBuilder
    private func devicePicker(shape: CanvasShapeModel, shapeId: UUID) -> some View {
        DevicePickerMenu(
            category: shape.deviceCategory ?? .iphone,
            frameId: shape.deviceFrameId,
            allowsNoDevice: false,
            presentation: .toolbar,
            bodyColor: shape.deviceCategory != .invisible && shape.resolvedDeviceFrame?.isModelBacked != false ? deviceBodyColorBinding(shapeId) : nil,
            bodyColorLabel: "Device color",
            canResetBodyColor: hasDeviceBodyColorOverride(shapeId),
            onResetBodyColor: { resetDeviceBodyColor(shapeId) },
            onSelectCategory: { cat in
                selectAbstractDevice(shapeId: shapeId, category: cat)
            },
            onSelectFrame: { frame in
                selectRealFrame(shapeId: shapeId, frame: frame)
            }
        )
        .help(devicePickerHelp(shape: shape))
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
        let imageSize = resolved.displayImageFileName.flatMap { state.screenshotImages[$0] }?.size
        resolved.selectAbstractDevice(category, screenshotImageSize: imageSize)
        state.updateShape(resolved)
    }

    private func selectRealFrame(shapeId: UUID, frame: DeviceFrame) {
        guard let i = idx(for: shapeId) else { return }
        var resolved = resolvedShape(at: i.row, shapeIdx: i.shape)
        resolved.selectRealFrame(frame)
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

    private func deviceModelRotationBinding(
        _ shapeId: UUID,
        _ keyPath: WritableKeyPath<CanvasShapeModel, Double?>,
        defaultValue: KeyPath<CanvasShapeModel, Double>
    ) -> Binding<Double> {
        Binding(
            get: {
                guard let i = idx(for: shapeId) else {
                    return CanvasShapeModel.placeholder[keyPath: defaultValue]
                }
                let shape = resolvedShape(at: i.row, shapeIdx: i.shape)
                return shape[keyPath: keyPath] ?? shape[keyPath: defaultValue]
            },
            set: { newValue in
                guard let i = idx(for: shapeId) else { return }
                var resolved = resolvedShape(at: i.row, shapeIdx: i.shape)
                resolved[keyPath: keyPath] = newValue
                state.updateShapeContinuous(resolved)
            }
        )
    }

    private func hasDeviceModelRotationOverride(_ shapeId: UUID) -> Bool {
        guard let i = idx(for: shapeId) else { return false }
        let shape = state.rows[i.row].shapes[i.shape]
        return shape.devicePitch != nil || shape.deviceYaw != nil
    }

    private func resetDeviceModelRotation(_ shapeId: UUID) {
        guard let i = idx(for: shapeId) else { return }
        var resolved = resolvedShape(at: i.row, shapeIdx: i.shape)
        resolved.resetDeviceModelRotation()
        state.updateShape(resolved)
    }

    private func fillStyleBinding(_ shapeId: UUID) -> Binding<BackgroundStyle> {
        Binding(
            get: {
                guard let i = idx(for: shapeId) else { return .color }
                return state.rows[i.row].shapes[i.shape].resolvedFillStyle
            },
            set: { newValue in
                guard let i = idx(for: shapeId) else { return }
                var resolved = resolvedShape(at: i.row, shapeIdx: i.shape)
                resolved.fillStyle = newValue == .color ? nil : newValue
                if newValue == .gradient && resolved.fillGradientConfig == nil {
                    resolved.fillGradientConfig = GradientConfig()
                }
                if newValue == .image && resolved.fillImageConfig == nil {
                    resolved.fillImageConfig = BackgroundImageConfig()
                }
                state.updateShape(resolved)
            }
        )
    }

    // MARK: - Text Popover

    @ViewBuilder
    private func textPopoverButton(shape: CanvasShapeModel, shapeId: UUID) -> some View {
        Button {
            isTextPopoverPresented.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "textformat")
                Text(textPopoverSummary(shape: shape))
                    .monospacedDigit()
                    .lineLimit(1)
                    .transaction { $0.animation = nil }
            }
        }
        .buttonStyle(.borderless)
        .help("Text")
        .popover(isPresented: $isTextPopoverPresented, arrowEdge: .top) {
            textPopoverContent(shape: shape, shapeId: shapeId)
                .padding(12)
                .frame(width: 280)
        }
    }

    private func textPopoverSummary(shape: CanvasShapeModel) -> String {
        let fontName = shape.fontName?.isEmpty == false ? shape.fontName! : "System"
        let size = Int(shape.fontSize ?? Self.defaultFontSize)
        let weight: String
        switch shape.fontWeight ?? 400 {
        case 300: weight = "Light"
        case 500: weight = "Medium"
        case 700: weight = "Bold"
        default: weight = "Regular"
        }
        return "\(fontName) \(size) \(weight)"
    }

    @ViewBuilder
    private func textPopoverContent(shape: CanvasShapeModel, shapeId: UUID) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Font
            LabeledContent("Font") {
                FontPicker(
                    selection: shapeBinding(shapeId, \.fontName, default: ""),
                    customFonts: state.customFonts,
                    onImportFont: { url in state.importCustomFont(from: url) }
                )
            }

            // Size & Weight
            LabeledContent("Size") {
                HStack(spacing: 4) {
                    HStack(spacing: 0) {
                        TextField("", text: $editingFontSize, onEditingChanged: { editing in
                            if editing {
                                isFontSizeFieldActive = true
                            } else {
                                commitFontSize(shapeId: shapeId)
                            }
                        })
                        .focused($focusedField, equals: .fontSize)
                        .frame(width: 48)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        .onAppear {
                            editingFontSize = currentFontSizeString(for: shapeId)
                        }
                        .onChange(of: shapeId) {
                            isFontSizeFieldActive = false
                            editingFontSize = currentFontSizeString(for: shapeId)
                        }
                        .onChange(of: shape.fontSize) {
                            guard !isFontSizeFieldActive else { return }
                            editingFontSize = currentFontSizeString(for: shapeId)
                        }
                        .onChange(of: editingFontSize) {
                            guard isFontSizeFieldActive else { return }
                            if let value = Int(editingFontSize), let i = idx(for: shapeId) {
                                var resolved = resolvedShape(at: i.row, shapeIdx: i.shape)
                                resolved.fontSize = clampedFontSize(value)
                                syncRichTextIfNeeded(in: &resolved, property: .fontSize)
                                state.updateShapeContinuous(resolved)
                            }
                        }

                        Menu {
                            ForEach(Self.fontSizePresets, id: \.self) { size in
                                Button("\(size)") {
                                    editingFontSize = "\(size)"
                                    commitFontSize(shapeId: shapeId)
                                }
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .frame(width: 14, height: 20)
                                .contentShape(Rectangle())
                        }
                        .menuStyle(.button)
                        .menuIndicator(.hidden)
                        .fixedSize()
                    }

                    Picker("", selection: shapeBinding(shapeId, \.fontWeight, default: 400)) {
                        Text("Light").tag(300)
                        Text("Regular").tag(400)
                        Text("Medium").tag(500)
                        Text("Bold").tag(700)
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }
            }

            Divider()

            // Alignment
            LabeledContent("Align") {
                HStack(spacing: 8) {
                    Picker("", selection: shapeBinding(shapeId, \.textAlign, default: .center)) {
                        Image(systemName: "text.alignleft").tag(TextAlign.left)
                        Image(systemName: "text.aligncenter").tag(TextAlign.center)
                        Image(systemName: "text.alignright").tag(TextAlign.right)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 90)
                    .help("Horizontal alignment")

                    Picker("", selection: shapeBinding(shapeId, \.textVerticalAlign, default: .center)) {
                        Image(systemName: "arrow.up.to.line").tag(TextVerticalAlign.top)
                        Image(systemName: "arrow.up.and.down").tag(TextVerticalAlign.center)
                        Image(systemName: "arrow.down.to.line").tag(TextVerticalAlign.bottom)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 90)
                    .help("Vertical alignment")
                }
            }

            // Style toggles
            HStack(spacing: 12) {
                Toggle("Italic", isOn: shapeBinding(shapeId, \.italic, default: false))
                    .toggleStyle(.switch)
                    .controlSize(.small)

                Toggle("Uppercase", isOn: shapeBinding(shapeId, \.uppercase, default: false))
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            Divider()

            // Tracking
            LabeledContent("Letter Spacing") {
                let trackingBinding = shapeBinding(shapeId, \.letterSpacing, default: 0)
                HStack(spacing: 4) {
                    Slider(value: trackingBinding, in: -5...30)
                        .frame(width: 120)

                    Text(verbatim: String(format: "%.1f", trackingBinding.wrappedValue))
                        .frame(width: 32, alignment: .trailing)
                        .onTapGesture(count: 2) { trackingBinding.wrappedValue = 0 }
                        .help("Double-click to reset")
                }
            }

            // Line height
            LabeledContent("Line Spacing") {
                HStack(spacing: 0) {
                    TextField("", text: $editingLineHeight, onEditingChanged: { editing in
                        if editing {
                            isLineHeightFieldActive = true
                        } else {
                            commitLineHeight(shapeId: shapeId)
                        }
                    })
                    .focused($focusedField, equals: .lineHeight)
                    .frame(width: 48)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .onAppear {
                        editingLineHeight = currentLineHeightString(for: shapeId)
                    }
                    .onChange(of: shapeId) {
                        isLineHeightFieldActive = false
                        editingLineHeight = currentLineHeightString(for: shapeId)
                    }
                    .onChange(of: shape.lineHeightMultiple) {
                        guard !isLineHeightFieldActive else { return }
                        editingLineHeight = currentLineHeightString(for: shapeId)
                    }
                    .onChange(of: editingLineHeight) {
                        guard isLineHeightFieldActive else { return }
                        if let value = Int(editingLineHeight), let i = idx(for: shapeId) {
                            var resolved = resolvedShape(at: i.row, shapeIdx: i.shape)
                            resolved.lineHeightMultiple = TextLayoutStyle.clampLineHeightMultiple(CGFloat(value) / 100.0)
                            resolved.lineSpacing = nil
                            syncRichTextIfNeeded(in: &resolved, property: .lineHeight)
                            state.updateShapeContinuous(resolved)
                        }
                    }

                    Menu {
                        ForEach(Self.lineHeightPresets, id: \.self) { preset in
                            Button("\(preset)%") {
                                editingLineHeight = "\(preset)"
                                commitLineHeight(shapeId: shapeId)
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .frame(width: 14, height: 20)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.button)
                    .menuIndicator(.hidden)
                    .fixedSize()

                    Text("%")
                        .foregroundStyle(.secondary)
                        .padding(.leading, 2)
                }
            }

            if shape.hasRichText {
                Divider()
                Button("Clear Formatting") {
                    guard let i = idx(for: shapeId) else { return }
                    var updated = resolvedShape(at: i.row, shapeIdx: i.shape)
                    updated.richText = nil
                    state.updateShape(updated)
                }
                .font(.system(size: 11))
            }
        }
        .font(.system(size: 11))
        .controlSize(.small)
    }

}
