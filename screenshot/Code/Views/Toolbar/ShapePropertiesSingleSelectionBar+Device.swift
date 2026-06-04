import SwiftUI

extension ShapePropertiesSingleSelectionBar {
    // MARK: - Device Picker

    /// Shared device picker used across toolbar/settings/inspector.
    @ViewBuilder
    func devicePicker(shape: CanvasShapeModel, shapeId: UUID) -> some View {
        DevicePickerMenu(
            category: shape.deviceCategory ?? .iphone,
            frameId: shape.deviceFrameId,
            allowsNoDevice: false,
            presentation: .toolbar,
            bodyColor: shape.deviceCategory != .invisible && shape.resolvedDeviceFrame?.isModelBacked != false ? deviceBodyColorBinding(shapeId) : nil,
            bodyColorLabel: String(localized: "Device color"),
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

    func devicePickerHelp(shape: CanvasShapeModel) -> LocalizedStringKey {
        if let frameId = shape.deviceFrameId, let frame = DeviceFrameCatalog.frame(for: frameId) {
            return "Current device frame: \(frame.label)"
        }
        return "Current abstract device: \((shape.deviceCategory ?? .iphone).label)"
    }

    func selectAbstractDevice(shapeId: UUID, category: DeviceCategory) {
        guard let i = idx(for: shapeId) else { return }
        var resolved = resolvedShape(at: i.row, shapeIdx: i.shape)
        let imageSize = resolved.displayImageFileName.flatMap { state.screenshotImages[$0] }?.size
        resolved.selectAbstractDevice(category, screenshotImageSize: imageSize)
        state.updateShape(resolved)
    }

    func selectRealFrame(shapeId: UUID, frame: DeviceFrame) {
        guard let i = idx(for: shapeId) else { return }
        var resolved = resolvedShape(at: i.row, shapeIdx: i.shape)
        resolved.selectRealFrame(frame)
        state.updateShape(resolved)
    }

    func deviceBodyColorBinding(_ shapeId: UUID) -> Binding<Color> {
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

    func hasDeviceBodyColorOverride(_ shapeId: UUID) -> Bool {
        guard let i = idx(for: shapeId) else { return false }
        return state.rows[i.row].shapes[i.shape].deviceBodyColorData != nil
    }

    func resetDeviceBodyColor(_ shapeId: UUID) {
        guard let i = idx(for: shapeId) else { return }
        guard state.rows[i.row].shapes[i.shape].type == .device else { return }
        var resolved = resolvedShape(at: i.row, shapeIdx: i.shape)
        resolved.deviceBodyColorData = nil
        state.updateShape(resolved)
    }

    func deviceModelRotationBinding(
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

    func hasDeviceModelRotationOverride(_ shapeId: UUID) -> Bool {
        guard let i = idx(for: shapeId) else { return false }
        let shape = state.rows[i.row].shapes[i.shape]
        return shape.devicePitch != nil || shape.deviceYaw != nil
    }

    func resetDeviceModelRotation(_ shapeId: UUID) {
        guard let i = idx(for: shapeId) else { return }
        var resolved = resolvedShape(at: i.row, shapeIdx: i.shape)
        resolved.resetDeviceModelRotation()
        state.updateShape(resolved)
    }

    func optionalConfigBinding<T: Equatable>(
        _ shapeId: UUID,
        _ keyPath: WritableKeyPath<CanvasShapeModel, T?>,
        fallback: T,
        isEmpty: @escaping (T) -> Bool
    ) -> Binding<T> {
        Binding(
            get: {
                guard let i = idx(for: shapeId) else { return fallback }
                return state.rows[i.row].shapes[i.shape][keyPath: keyPath] ?? fallback
            },
            set: { newValue in
                guard let i = idx(for: shapeId) else { return }
                var resolved = resolvedShape(at: i.row, shapeIdx: i.shape)
                resolved[keyPath: keyPath] = isEmpty(newValue) ? nil : newValue
                state.updateShapeContinuous(resolved)
            }
        )
    }

    func fillStyleBinding(_ shapeId: UUID) -> Binding<BackgroundStyle> {
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
}
