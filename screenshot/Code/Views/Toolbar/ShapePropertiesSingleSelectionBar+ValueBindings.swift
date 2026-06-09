import SwiftUI

extension ShapePropertiesSingleSelectionBar {
    func currentFontSizeString(for shapeId: UUID) -> String {
        guard let i = idx(for: shapeId) else { return "\(Int(Self.defaultFontSize))" }
        return "\(Int(resolvedShape(at: i.row, shapeIdx: i.shape).fontSize ?? Self.defaultFontSize))"
    }

    func clampedFontSize(_ value: Int) -> CGFloat {
        min(max(CGFloat(value), Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound)
    }

    func commitFontSize(to shapeId: UUID?) {
        isFontSizeFieldActive = false
        guard let shapeId, let i = idx(for: shapeId) else { return }
        guard let value = Int(editingFontSize) else {
            editingFontSize = currentFontSizeString(for: shapeId)
            return
        }
        let clamped = clampedFontSize(value)
        var resolved = resolvedShape(at: i.row, shapeIdx: i.shape)
        if resolved.fontSize != clamped {
            resolved.fontSize = clamped
            RichTextUtils.syncShapeStyleIfNeeded(in: &resolved, property: .fontSize)
            state.updateShape(resolved)
        }
        editingFontSize = "\(Int(clamped))"
    }

    func currentOpacityString(for shapeId: UUID) -> String {
        guard let i = idx(for: shapeId) else { return "100" }
        return "\(Int((state.rows[i.row].shapes[i.shape].opacity * 100).rounded()))"
    }

    func commitOpacity(to shapeId: UUID?) {
        isOpacityFieldActive = false
        guard let shapeId, let i = idx(for: shapeId) else { return }
        guard let value = Int(editingOpacity) else {
            editingOpacity = currentOpacityString(for: shapeId)
            return
        }
        let clamped = min(max(value, 0), 100)
        var resolved = resolvedShape(at: i.row, shapeIdx: i.shape)
        let newOpacity = Double(clamped) / 100.0
        if resolved.opacity != newOpacity {
            resolved.opacity = newOpacity
            state.updateShape(resolved)
        }
        editingOpacity = "\(clamped)"
    }

    func currentRotationString(for shapeId: UUID) -> String {
        guard let i = idx(for: shapeId) else { return "0" }
        return formatRotation(state.rows[i.row].shapes[i.shape].rotation)
    }

    func formatRotation(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded()
            ? String(format: "%.0f", rounded)
            : String(format: "%.1f", rounded)
    }

    func commitRotation(to shapeId: UUID?) {
        isRotationFieldActive = false
        guard let shapeId, let i = idx(for: shapeId) else { return }
        let trimmed = editingRotation.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(trimmed) else {
            editingRotation = currentRotationString(for: shapeId)
            return
        }
        var normalized = value.truncatingRemainder(dividingBy: 360)
        if normalized < 0 { normalized += 360 }
        var resolved = resolvedShape(at: i.row, shapeIdx: i.shape)
        if resolved.rotation != normalized {
            resolved.rotation = normalized
            state.updateShape(resolved)
        }
        editingRotation = formatRotation(normalized)
    }

    func resetRotation(shapeId: UUID) {
        guard let i = idx(for: shapeId) else { return }
        var resolved = resolvedShape(at: i.row, shapeIdx: i.shape)
        guard resolved.rotation != 0 else { return }
        resolved.rotation = 0
        state.updateShape(resolved)
        editingRotation = "0"
    }

    func currentLineHeightString(for shapeId: UUID) -> String {
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

    func commitLineHeight(to shapeId: UUID?) {
        isLineHeightFieldActive = false
        guard let shapeId, let i = idx(for: shapeId) else { return }
        guard let value = Int(editingLineHeight) else {
            editingLineHeight = currentLineHeightString(for: shapeId)
            return
        }
        let clamped = TextLayoutStyle.clampLineHeightMultiple(CGFloat(value) / 100.0)
        var resolved = resolvedShape(at: i.row, shapeIdx: i.shape)
        if resolved.lineHeightMultiple != clamped || resolved.lineSpacing != nil {
            resolved.lineHeightMultiple = clamped
            resolved.lineSpacing = nil
            RichTextUtils.syncShapeStyleIfNeeded(in: &resolved, property: .lineHeight)
            state.updateShape(resolved)
        }
        editingLineHeight = "\(Int((clamped * 100).rounded()))"
    }

    func richTextStyleProperty<T>(for keyPath: WritableKeyPath<CanvasShapeModel, T>) -> RichTextUtils.ShapeStyleProperty? {
        let anyKeyPath = keyPath as AnyKeyPath
        if anyKeyPath == \CanvasShapeModel.color { return .color }
        return nil
    }

    func richTextStyleProperty<T>(for keyPath: WritableKeyPath<CanvasShapeModel, T?>) -> RichTextUtils.ShapeStyleProperty? {
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
    func shapeBinding<T>(_ shapeId: UUID, _ keyPath: WritableKeyPath<CanvasShapeModel, T>, continuous: Bool = false) -> Binding<T> where T: Sendable {
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
                RichTextUtils.syncShapeStyleIfNeeded(in: &resolved, property: richTextStyleProperty(for: keyPath))
                if continuous {
                    state.updateShapeContinuous(resolved)
                } else {
                    state.updateShape(resolved)
                }
            }
        )
    }

    /// Overload for optional properties with a default value.
    func shapeBinding<T>(_ shapeId: UUID, _ keyPath: WritableKeyPath<CanvasShapeModel, T?>, default defaultValue: T, continuous: Bool = false) -> Binding<T> where T: Sendable {
        Binding(
            get: {
                guard let i = idx(for: shapeId) else { return defaultValue }
                return resolvedShape(at: i.row, shapeIdx: i.shape)[keyPath: keyPath] ?? defaultValue
            },
            set: { newValue in
                guard let i = idx(for: shapeId) else { return }
                var resolved = resolvedShape(at: i.row, shapeIdx: i.shape)
                resolved[keyPath: keyPath] = newValue
                RichTextUtils.syncShapeStyleIfNeeded(in: &resolved, property: richTextStyleProperty(for: keyPath))
                if continuous {
                    state.updateShapeContinuous(resolved)
                } else {
                    state.updateShape(resolved)
                }
            }
        )
    }

    func fontWeightBinding(_ shapeId: UUID) -> Binding<Int> {
        Binding(
            get: {
                guard let i = idx(for: shapeId) else { return 400 }
                let shape = resolvedShape(at: i.row, shapeIdx: i.shape)
                return CustomFontRegistry.controlState(for: shape)?.effectiveWeight ?? shape.fontWeight ?? 400
            },
            set: { newValue in
                guard let i = idx(for: shapeId) else { return }
                var resolved = resolvedShape(at: i.row, shapeIdx: i.shape)
                RichTextUtils.applyFontWeightUpdate(to: &resolved, weight: newValue)
                state.updateShape(resolved)
            }
        )
    }

    func italicBinding(_ shapeId: UUID) -> Binding<Bool> {
        Binding(
            get: {
                guard let i = idx(for: shapeId) else { return false }
                let shape = resolvedShape(at: i.row, shapeIdx: i.shape)
                return CustomFontRegistry.controlState(for: shape)?.effectiveItalic ?? shape.italic ?? false
            },
            set: { newValue in
                guard let i = idx(for: shapeId) else { return }
                var resolved = resolvedShape(at: i.row, shapeIdx: i.shape)
                RichTextUtils.applyItalicUpdate(to: &resolved, italic: newValue)
                state.updateShape(resolved)
            }
        )
    }

    func applyImportedFontSelection(_ imported: ImportedCustomFontSelection, to shapeId: UUID) {
        guard let i = idx(for: shapeId) else { return }
        var resolved = resolvedShape(at: i.row, shapeIdx: i.shape)
        RichTextUtils.applyImportedFontSelection(imported, to: &resolved, property: .fontName)
        state.updateShape(resolved)
    }

    func lineHeightBinding(_ shapeId: UUID) -> Binding<CGFloat> {
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
                RichTextUtils.syncShapeStyleIfNeeded(in: &resolved, property: .lineHeight)
                state.updateShape(resolved)
            }
        )
    }

    func nsFontWeight(_ weight: Int) -> NSFont.Weight {
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
}
