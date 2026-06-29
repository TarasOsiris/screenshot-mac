import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
let propertiesNumericFieldWidth: CGFloat = 44
let propertiesOpacityFieldWidth: CGFloat = 40
let propertiesFontFieldWidth: CGFloat = 48
let propertiesTrackingValueWidth: CGFloat = 32
let propertiesSliderValueWidth: CGFloat = 28
#else
let propertiesNumericFieldWidth: CGFloat = 56
let propertiesOpacityFieldWidth: CGFloat = 52
let propertiesFontFieldWidth: CGFloat = 56
let propertiesTrackingValueWidth: CGFloat = 40
let propertiesSliderValueWidth: CGFloat = 36
#endif

struct ShapePropertiesSingleSelectionBar: View {
    static let defaultFontSize: CGFloat = CanvasShapeModel.defaultFontSize
    static let fontSizeRange: ClosedRange<CGFloat> = 8...400
    static let fontSizePresets: [Int] = CanvasShapeModel.fontSizePresets
    @Bindable var state: AppState
    @State var isReplacingSvg = false
    #if os(macOS)
    @State var isReplacingFillImage = false
    #endif
    @State var isFillPopoverPresented = false
    @State var isTextPopoverPresented = false
    @State var isTextLocalizationPopoverPresented = false
    @State var isTextBackgroundPopoverPresented = false
    @State var editingFontSize: String = ""
    @State var isFontSizeFieldActive = false
    @State var editingLineHeight: String = ""
    @State var isLineHeightFieldActive = false
    @State var editingOpacity: String = ""
    @State var isOpacityFieldActive = false
    @State var editingRotation: String = ""
    @State var isRotationFieldActive = false
    @FocusState var focusedField: Field?
    enum Field: Hashable { case opacity, fontSize, lineHeight, rotation }
    static let lineHeightPresets: [Int] = [50, 60, 70, 80, 90, 100, 110, 120, 130, 140, 150, 175, 200]

    var rowIndex: Int? { state.selectedRowIndex }
    var shapeIndex: Int? {
        guard let rowIndex, let shapeId = state.selectedShapeId else { return nil }
        return state.rows[rowIndex].shapes.firstIndex { $0.id == shapeId }
    }
    var canBringToFront: Bool {
        guard let rowIndex, let shapeIndex else { return false }
        return shapeIndex < state.rows[rowIndex].shapes.count - 1
    }
    var canSendToBack: Bool {
        guard let shapeIndex else { return false }
        return shapeIndex > 0
    }

    func pickAndReplaceImage(for shapeId: UUID) {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let image = NSImage.fromSecurityScopedURL(url) else { return }
        state.saveImage(image, for: shapeId)
        #endif
        // iPad routes image selection through ImageSourceMenu (Photo Library / Camera / Files)
        // via `onImageSelected`, so this NSOpenPanel path is macOS-only.
    }

    func idx(for shapeId: UUID) -> (row: Int, shape: Int)? {
        guard let ri = rowIndex, ri < state.rows.count,
              let si = state.rows[ri].shapes.firstIndex(where: { $0.id == shapeId })
        else { return nil }
        return (ri, si)
    }

    /// The selected shape with locale overrides applied (for display).
    func resolvedShape(at rowIndex: Int, shapeIdx: Int) -> CanvasShapeModel {
        let base = state.rows[rowIndex].shapes[shapeIdx]
        return LocaleService.resolveShape(base, localeState: state.localeState)
    }

    /// Whether the selected shape has any locale override for the active locale.
    var hasLocaleOverride: Bool {
        guard let shapeId = state.selectedShapeId, !state.localeState.isBaseLocale else { return false }
        return state.shapeHasActiveLocaleOverride(shapeId)
    }

    /// Whether a shape has a locale image override for the active locale.
    func hasLocaleImageOverride(_ shapeId: UUID) -> Bool {
        guard !state.localeState.isBaseLocale else { return false }
        return state.localeState.override(forCode: state.localeState.activeLocaleCode, shapeId: shapeId)?.overrideImageFileName != nil
    }

    var body: some View {
        if let rowIndex, let shapeIdx = shapeIndex {
            let shape = resolvedShape(at: rowIndex, shapeIdx: shapeIdx)
            let shapeId = shape.id

            HStack(spacing: 0) {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ShapePropertiesBadge(shape: shape)

                        if shape.type == .device {
                            DeviceShapeControls(
                                shape: shape,
                                showsLocaleImageReset: hasLocaleImageOverride(shapeId),
                                onPickImage: { pickAndReplaceImage(for: shapeId) },
                                onImageSelected: { state.saveImage($0, for: shapeId) },
                                onResetLocaleImage: { state.resetLocaleImageOverride(shapeId: shapeId) }
                            ) {
                                devicePicker(shape: shape, shapeId: shapeId)
                            }
                        }

                        if shape.type == .device
                            && shape.deviceCategory == .androidPhone
                            && shape.deviceFrameId == nil {
                            let hideCamera = shapeBinding(shapeId, \.hideCameraCutout, default: false)
                            ShapePropertiesSection {
                                Toggle("Camera", isOn: Binding(
                                    get: { !hideCamera.wrappedValue },
                                    set: { hideCamera.wrappedValue = !$0 }
                                ))
                                .toggleStyle(.switch)
                                .compactControlSize()
                                .help("Show camera cutout on the abstract Android frame")
                            }
                        }

                        if shape.supportsDeviceModelRotation {
                            ShapeDeviceModelRotationControls(
                                pitch: deviceModelRotationBinding(shapeId, \.devicePitch, defaultValue: \.resolvedDevicePitch),
                                yaw: deviceModelRotationBinding(shapeId, \.deviceYaw, defaultValue: \.resolvedDeviceYaw),
                                canReset: hasDeviceModelRotationOverride(shapeId),
                                onReset: { resetDeviceModelRotation(shapeId) },
                                bodyMaterial: optionalConfigBinding(shapeId, \.deviceBodyMaterial, fallback: DeviceBodyMaterial(), isEmpty: \.isEmpty),
                                lighting: optionalConfigBinding(shapeId, \.deviceLighting, fallback: DeviceLighting(), isEmpty: \.isEmpty)
                            )
                        }

                        ShapeShadowControls(
                            shadow: optionalConfigBinding(shapeId, \.shadow, fallback: ShadowConfig(), isEmpty: \.isEmpty)
                        )

                        if shape.type.supportsFill {
                            ShapePropertiesSection {
                                ShapeFillSwatchButton(
                                    shape: shape,
                                    isPresented: $isFillPopoverPresented,
                                    backgroundStyle: fillStyleBinding(shapeId),
                                    bgColor: shapeBinding(shapeId, \.color),
                                    gradientConfig: shapeBinding(shapeId, \.fillGradientConfig, default: GradientConfig(), continuous: true),
                                    backgroundImageConfig: shapeBinding(shapeId, \.fillImageConfig, default: BackgroundImageConfig(), continuous: true),
                                    backgroundImage: (idx(for: shapeId).flatMap { i in
                                        state.rows[i.row].shapes[i.shape].fillImageConfig?.fileName
                                    }).flatMap { state.screenshotImages[$0] },
                                    onChanged: { state.scheduleSave() },
                                    // macOS opens a file panel here; iPad picks via ImageSourceMenu
                                    // inside BackgroundImageEditor (→ onDropImage → saveShapeFillImage).
                                    onPickImage: {
                                        #if os(macOS)
                                        isReplacingFillImage = true
                                        #endif
                                    },
                                    onRemoveImage: { state.removeShapeFillImage(for: shapeId) },
                                    onDropImage: { image in state.saveShapeFillImage(image, for: shapeId) }
                                )
                            }
                        } else if shape.type != .device && shape.type != .svg && shape.type != .image {
                            ShapePropertiesSection {
                                ColorPicker("Fill color", selection: shapeBinding(shapeId, \.color), supportsOpacity: false)
                                    .labelsHidden()
                                    .frame(width: UIMetrics.ColorSwatch.inline)
                                    .help("Fill color")
                            }
                        }

                        ShapePropertiesSection {
                            ShapePropertiesControlGroup("Opacity") {
                                HStack(spacing: 0) {
                                    TextField("", text: $editingOpacity, onEditingChanged: { editing in
                                        if editing {
                                            isOpacityFieldActive = true
                                        } else {
                                            // Commit to the LIVE selection, not the captured shapeId:
                                            // SwiftUI keeps stale closures on a focused field after
                                            // selection changes. Fall back to the captured id only
                                            // when selection is no longer a single shape.
                                            commitOpacity(to: state.selectedShapeId ?? shapeId)
                                        }
                                    })
                                    .focused($focusedField, equals: .opacity)
                                    .frame(width: propertiesOpacityFieldWidth)
                                    .textFieldStyle(.roundedBorder)
                                    .multilineTextAlignment(.center)
                                    .integerKeyboard()
                                    .onAppear {
                                        editingOpacity = currentOpacityString(for: shapeId)
                                    }
                                    .onChange(of: shapeId) { oldId, newId in
                                        // Flush any uncommitted value to the shape we WERE
                                        // editing — oldId from onChange is reliable (unlike a
                                        // captured shapeId) — then rebind to the new selection.
                                        if isOpacityFieldActive { commitOpacity(to: oldId) }
                                        editingOpacity = currentOpacityString(for: newId)
                                        focusedField = nil
                                    }
                                    .onChange(of: shape.opacity) {
                                        guard !isOpacityFieldActive else { return }
                                        editingOpacity = currentOpacityString(for: shapeId)
                                    }
                                    .onSubmit {
                                        commitOpacity(to: state.selectedShapeId ?? shapeId)
                                    }

                                    Text("%")
                                        .font(.system(size: UIMetrics.FontSize.numericBadge))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        ShapePropertiesSection {
                            ShapePropertiesControlGroup("Rotation") {
                                Slider(value: shapeBinding(shapeId, \.rotation, continuous: true), in: 0...360)
                                    .frame(width: UIMetrics.SliderWidth.standard)

                                HStack(spacing: 0) {
                                    TextField("", text: $editingRotation, onEditingChanged: { editing in
                                        if editing {
                                            isRotationFieldActive = true
                                        } else {
                                            commitRotation(to: state.selectedShapeId ?? shapeId)
                                        }
                                    })
                                    .focused($focusedField, equals: .rotation)
                                    .frame(width: propertiesNumericFieldWidth)
                                    .textFieldStyle(.roundedBorder)
                                    .multilineTextAlignment(.center)
                                    .signedNumberKeyboard()
                                    .onAppear {
                                        editingRotation = currentRotationString(for: shapeId)
                                    }
                                    .onChange(of: shapeId) { oldId, newId in
                                        // Flush to the shape we were editing (reliable oldId),
                                        // then rebind to the new selection.
                                        if isRotationFieldActive { commitRotation(to: oldId) }
                                        editingRotation = currentRotationString(for: newId)
                                        focusedField = nil
                                    }
                                    .onChange(of: shape.rotation) {
                                        guard !isRotationFieldActive else { return }
                                        let next = currentRotationString(for: shapeId)
                                        if editingRotation != next { editingRotation = next }
                                    }
                                    .onSubmit {
                                        commitRotation(to: state.selectedShapeId ?? shapeId)
                                    }

                                    Text("°")
                                        .font(.system(size: UIMetrics.FontSize.numericBadge))
                                        .foregroundStyle(.secondary)
                                }

                                if shape.rotation != 0 {
                                    ActionButton(icon: "arrow.counterclockwise", tooltip: "Reset rotation") {
                                        resetRotation(shapeId: shapeId)
                                    }
                                }
                            }
                        }

                        if shape.type == .rectangle || shape.type == .image || (shape.type == .device && shape.deviceCategory == .invisible) {
                            ShapePropertiesSection {
                                ShapePropertiesControlGroup("Radius") {
                                    Slider(value: shapeBinding(shapeId, \.borderRadius, continuous: true), in: 0...500)
                                        .frame(width: UIMetrics.SliderWidth.standard)

                                    Text(verbatim: "\(Int(shape.borderRadius))")
                                        .frame(width: propertiesSliderValueWidth, alignment: .trailing)
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
                                onImageSelected: { state.saveImage($0, for: shapeId) },
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
                            ShapePropertiesSection {
                                textBackgroundButton(shape: shape, shapeId: shapeId)
                            }
                            if state.localeState.nonBaseLocaleCount > 0 {
                                ShapePropertiesSection {
                                    textLocalizationButton(shape: shape, shapeId: shapeId)
                                }
                            }
                        }

                        ShapePropertiesSection {
                            Toggle("Clip to Frame", isOn: shapeBinding(shapeId, \.clipToTemplate, default: false))
                                .toggleStyle(.switch)
                                .compactControlSize()
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
                    .padding(.horizontal, ShapePropertiesSectionLayout.horizontalPadding)
                    .padding(.vertical, ShapePropertiesSectionLayout.verticalPadding)
                }
                .scrollIndicators(.hidden)

                Spacer(minLength: 0)

                #if os(macOS)
                ActionButton(icon: "xmark", tooltip: "Deselect shape (Esc)", frameSize: 24) {
                    state.selectedShapeIds = []
                }
                .padding(.trailing, 8)
                #else
                ActionButton(icon: "xmark", tooltip: "Deselect shape", frameSize: 24) {
                    state.selectedShapeIds = []
                }
                .padding(.trailing, 8)
                #endif
            }
            .font(.system(size: UIMetrics.FontSize.body))
            .compactControlSize()
            .modifier(PropertiesBarChrome())
            // macOS-only: the fill swatch's "pick image" opens this file panel. iPad picks the
            // fill image through ImageSourceMenu inside BackgroundImageEditor (→ saveShapeFillImage).
            #if os(macOS)
            .fileImporter(isPresented: $isReplacingFillImage, allowedContentTypes: [.image]) { result in
                if case .success(let url) = result,
                   let image = NSImage.fromSecurityScopedURL(url) {
                    state.saveShapeFillImage(image, for: shapeId)
                }
            }
            #endif
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
}
