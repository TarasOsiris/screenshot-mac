import SwiftUI

/// The editing logic behind the multi-selection controls, shared by the properties bar and the
/// selection inspector. Every write fans out to the whole selection; reads show the first shape.
protocol MultiShapeEditing {
    var state: AppState { get }
}

extension MultiShapeEditing {
    var selectedShapes: [CanvasShapeModel] {
        guard let rowIndex = state.selectedRowIndex else { return [] }
        let ids = state.selectedShapeIds
        return state.rows[rowIndex].shapes
            .filter { ids.contains($0.id) }
            .map { LocaleService.resolveShape($0, localeState: state.localeState) }
    }

    func commonShapeType(of shapes: [CanvasShapeModel]) -> ShapeType? {
        shapes.dropFirst().allSatisfy({ $0.type == shapes.first?.type }) ? shapes.first?.type : nil
    }

    func setOutlineOnSelection(_ enabled: Bool) {
        state.updateShapes(state.selectedShapeIds) { shape in
            shape.outlineColor = enabled ? CanvasShapeModel.defaultOutlineColor : nil
            shape.outlineWidth = enabled ? CanvasShapeModel.defaultOutlineWidth : nil
        }
    }

    func resetRotationOnSelection() {
        state.updateShapes(state.selectedShapeIds) { shape in
            shape.rotation = 0
        }
    }

    func selectAbstractDeviceOnSelection(_ category: DeviceCategory) {
        state.updateShapes(state.selectedShapeIds) {
            let imageSize = category == .invisible
                ? $0.displayImageFileName.flatMap { state.screenshotImages[$0] }?.size
                : nil
            $0.selectAbstractDevice(category, screenshotImageSize: imageSize)
        }
    }

    func selectRealFrameOnSelection(_ frame: DeviceFrame) {
        state.updateShapes(state.selectedShapeIds) { $0.selectRealFrame(frame) }
    }

    func applyImportedFontSelectionOnSelection(_ imported: ImportedCustomFontSelection) {
        state.updateShapes(state.selectedShapeIds) { shape in
            RichTextUtils.applyImportedFontSelection(imported, to: &shape, property: .fontName)
        }
    }

    var firstTextShape: CanvasShapeModel? {
        firstResolvedSelectedShape { $0.type == .text }
    }

    func firstResolvedSelectedShape(where predicate: (CanvasShapeModel) -> Bool = { _ in true }) -> CanvasShapeModel? {
        guard let rowIndex = state.selectedRowIndex else { return nil }
        let ids = state.selectedShapeIds
        guard !ids.isEmpty else { return nil }
        for shape in state.rows[rowIndex].shapes where ids.contains(shape.id) && predicate(shape) {
            return LocaleService.resolveShape(shape, localeState: state.localeState)
        }
        return nil
    }

    func showsMultiFontWeightPicker(primary: CustomFontControlState?, textShapes: [CanvasShapeModel]) -> Bool {
        guard let primary else { return true }
        return primary.showsWeightPicker && textShapes.allSatisfy { shape in
            guard let state = CustomFontRegistry.controlState(for: shape) else { return true }
            return state.showsWeightPicker && state.availableWeights == primary.availableWeights
        }
    }

    func showsMultiItalicToggle(textShapes: [CanvasShapeModel]) -> Bool {
        textShapes.allSatisfy { shape in
            CustomFontRegistry.controlState(for: shape)?.showsItalicToggle ?? true
        }
    }

    func multiFontNameBinding() -> Binding<String> {
        Binding(
            get: { firstTextShape?.fontName ?? "" },
            set: { newValue in
                state.updateShapes(state.selectedShapeIds) { shape in
                    shape.fontName = newValue
                    RichTextUtils.syncShapeStyleIfNeeded(in: &shape, property: .fontName)
                }
            }
        )
    }

    func multiFontWeightBinding(controlState: CustomFontControlState?) -> Binding<Int> {
        Binding(
            get: {
                controlState?.effectiveWeight ?? firstTextShape?.fontWeight ?? 400
            },
            set: { newValue in
                state.updateShapes(state.selectedShapeIds) { shape in
                    RichTextUtils.applyFontWeightUpdate(to: &shape, weight: newValue)
                }
            }
        )
    }

    func multiItalicBinding(controlState: CustomFontControlState?) -> Binding<Bool> {
        Binding(
            get: {
                controlState?.effectiveItalic ?? firstTextShape?.italic ?? false
            },
            set: { newValue in
                state.updateShapes(state.selectedShapeIds) { shape in
                    RichTextUtils.applyItalicUpdate(to: &shape, italic: newValue)
                }
            }
        )
    }

    /// Shared shadow binding for the selected devices: reads the first device's shadow
    /// and writes the edited config to all of them (clearing to nil when empty, matching
    /// the single-selection behavior).
    func multiShadowBinding() -> Binding<ShadowConfig> {
        Binding(
            get: {
                firstResolvedSelectedShape()?.shadow ?? ShadowConfig()
            },
            set: { newValue in
                state.updateShapesContinuous(state.selectedShapeIds) { shape in
                    shape.shadow = newValue.isEmpty ? nil : newValue
                }
            }
        )
    }

    // Slider-only binding: writes go through the throttled continuous path.
    func multiShapeBinding<T: Equatable & Sendable>(_ keyPath: WritableKeyPath<CanvasShapeModel, T>) -> Binding<T> {
        Binding(
            get: {
                firstResolvedSelectedShape()?[keyPath: keyPath] ?? CanvasShapeModel.placeholder[keyPath: keyPath]
            },
            set: { newValue in
                state.updateShapesContinuous(state.selectedShapeIds) { shape in
                    shape[keyPath: keyPath] = newValue
                }
            }
        )
    }

    func multiShapeOptionalBinding<T: Equatable & Sendable>(_ keyPath: WritableKeyPath<CanvasShapeModel, T?>, default defaultValue: T, continuous: Bool = false) -> Binding<T> {
        Binding(
            get: {
                firstResolvedSelectedShape()?[keyPath: keyPath] ?? defaultValue
            },
            set: { newValue in
                if continuous {
                    state.updateShapesContinuous(state.selectedShapeIds) { shape in
                        shape[keyPath: keyPath] = newValue
                    }
                } else {
                    state.updateShapes(state.selectedShapeIds) { shape in
                        shape[keyPath: keyPath] = newValue
                    }
                }
            }
        )
    }
}
