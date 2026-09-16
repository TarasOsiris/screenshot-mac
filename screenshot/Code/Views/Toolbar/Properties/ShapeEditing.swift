import SwiftUI

/// The editing logic behind every single-shape control, shared by the bottom properties bar and
/// the selection inspector — two layouts of the same controls. Conform a view that edits the
/// selected shape and it gets the binding factories, lookups and commits below.
///
/// No helper here takes a `CanvasShapeModel` to write back: pass a `shapeId` and resolve at call
/// time, or the value goes stale mid-burst (see `documentShape`).
protocol ShapeEditing {
    var state: AppState { get }
}

/// A numeric text field's in-progress text and whether the user is editing it.
struct ShapeFieldDraft {
    let text: Binding<String>
    let isActive: Binding<Bool>
}

enum ShapeTextDefaults {
    static let fontSizeRange: ClosedRange<CGFloat> = 8...400
    static let lineHeightPresets: [Int] = [50, 60, 70, 80, 90, 100, 110, 120, 130, 140, 150, 175, 200]
}

extension ShapeEditing {
    // MARK: - Lookup

    /// Resolved in any row, like the writes in `AppState.updateShape` — so a field flushing its
    /// draft to the shape it was editing still lands after the selection moved to another row.
    func idx(for shapeId: UUID) -> (row: Int, shape: Int)? {
        state.shapeLocation(for: shapeId).map { ($0.rowIndex, $0.shapeIndex) }
    }

    /// The document's value for the selected shape, with locale overrides applied — deliberately
    /// blind to an in-flight slider drag.
    ///
    /// **A container's `body` reads only this.** Controls read `editingShape` for what they drag;
    /// reading *that* in the container's `body` would put the ~30 Hz value in its tracking scope and
    /// rebuild every control section on every tick, which is the cost `LiveShapeEditSession` exists
    /// to remove.
    func documentShape(at rowIndex: Int, shapeIdx: Int) -> CanvasShapeModel {
        let base = state.rows[rowIndex].shapes[shapeIdx]
        return LocaleService.resolveShape(base, localeState: state.localeState)
    }

    /// The selected shape as a control must see it: the value an in-flight continuous edit is
    /// composing — which by design has not reached `rows` yet — else the document's.
    ///
    /// Reading the live value matters for writes as much as for display. A control that captured
    /// the document's shape mid-burst and wrote it back would revert the drag still settling.
    /// Observation attributes a read to whichever body is running when the getter fires, so a
    /// `Binding` built in `body` but read inside a leaf only invalidates that leaf. The live branch
    /// also never touches `rows`, so a control that hits it registers no dependency on the document.
    func editingShape(_ shapeId: UUID) -> CanvasShapeModel? {
        if let live = state.liveShapeEdit.liveShape(for: shapeId) { return live }
        return resolvedDocumentShape(shapeId)
    }

    /// What a geometry readout must *show*: the edited shape with an in-flight canvas gesture's
    /// frame laid over it, so X/Y/W/H and rotation track the pointer instead of freezing until
    /// mouse-up.
    ///
    /// **Display only** — every write still resolves through `editingShape`, so no control can
    /// persist a frame the pointer is still moving. On iPad the bar is on screen during a canvas
    /// drag, so a second finger really can reach a control mid-gesture.
    func liveGeometryShape(_ shapeId: UUID) -> CanvasShapeModel? {
        editingShape(shapeId).map { state.liveShapeGeometry.applied(to: $0) ?? $0 }
    }

    /// The same value, resolved from an index the caller already has. `shapeLocation` scans every
    /// row's shapes, and the readouts now re-resolve on every tick of a canvas gesture rather than
    /// once per commit — so the geometry fields look their shape up once instead of twice a tick.
    func liveGeometryShape(_ shapeId: UUID, at i: (row: Int, shape: Int)) -> CanvasShapeModel {
        let base = state.liveShapeEdit.liveShape(for: shapeId) ?? documentShape(at: i.row, shapeIdx: i.shape)
        return state.liveShapeGeometry.applied(to: base) ?? base
    }

    /// What a control that is never dragged should *display*. A burst only changes the properties
    /// being dragged, so a picker or toggle reading `editingShape` would re-render every tick of an
    /// unrelated slider for nothing. Writes still go through `editingShape`.
    func resolvedDocumentShape(_ shapeId: UUID) -> CanvasShapeModel? {
        idx(for: shapeId).map { documentShape(at: $0.row, shapeIdx: $0.shape) }
    }

    func canBringToFront(_ shapeId: UUID) -> Bool {
        guard let i = idx(for: shapeId) else { return false }
        return i.shape < state.rows[i.row].shapes.count - 1
    }

    func canSendToBack(_ shapeId: UUID) -> Bool {
        guard let i = idx(for: shapeId) else { return false }
        return i.shape > 0
    }

    /// macOS only: iPad routes image selection through `ImageSourceMenu` via `onImageSelected`.
    func pickAndReplaceImage(for shapeId: UUID) {
        Task { @MainActor in
            guard let image = await FilePicker.pickImage() else { return }
            state.saveImage(image, for: shapeId, source: .panel)
        }
    }

    func shapeFillImage(_ shapeId: UUID) -> NSImage? {
        (idx(for: shapeId).flatMap { i in
            state.rows[i.row].shapes[i.shape].fillImageConfig?.fileName
        }).flatMap { state.screenshotImages[$0] }
    }

    // MARK: - Font size & line height

    // The `current…` readouts feed `ShapePropertyField`, which reprograms its text as the model
    // moves — so for a continuously edited property they have to read the in-flight value, not
    // `rows`. They are closures evaluated inside the field, so the session read stays in that leaf.
    func currentFontSizeString(for shapeId: UUID) -> String {
        guard let shape = editingShape(shapeId) else { return "\(Int(CanvasShapeModel.defaultFontSize))" }
        return "\(Int(shape.fontSize ?? CanvasShapeModel.defaultFontSize))"
    }

    func clampedFontSize(_ value: Int) -> CGFloat {
        min(max(CGFloat(value), ShapeTextDefaults.fontSizeRange.lowerBound), ShapeTextDefaults.fontSizeRange.upperBound)
    }

    func commitFontSize(to shapeId: UUID?, draft: ShapeFieldDraft) {
        draft.isActive.wrappedValue = false
        guard let shapeId, var resolved = editingShape(shapeId) else { return }
        guard let value = Int(draft.text.wrappedValue) else {
            draft.text.wrappedValue = currentFontSizeString(for: shapeId)
            return
        }
        let clamped = clampedFontSize(value)
        if resolved.fontSize != clamped {
            resolved.fontSize = clamped
            RichTextUtils.syncShapeStyleIfNeeded(in: &resolved, property: .fontSize)
            state.updateShape(resolved)
        }
        draft.text.wrappedValue = "\(Int(clamped))"
    }

    /// Applies each keystroke as a coalesced-undo edit so the canvas tracks the field live.
    func applyFontSizeContinuously(fallbackShapeId: UUID, draft: ShapeFieldDraft) {
        let target = state.selectedShapeId ?? fallbackShapeId
        guard let value = Int(draft.text.wrappedValue), var resolved = editingShape(target) else { return }
        let newSize = clampedFontSize(value)
        // A no-op size (e.g. the field reprogrammed to the current value during an edit→commit
        // transition) must not run syncShapeStyle(.fontSize) — that flattens mixed per-run
        // rich-text sizes to one. Mirrors commitFontSize's guard.
        guard resolved.fontSize != newSize else { return }
        resolved.fontSize = newSize
        RichTextUtils.syncShapeStyleIfNeeded(in: &resolved, property: .fontSize)
        state.updateShapeContinuous(resolved)
    }

    func applyLineHeightContinuously(fallbackShapeId: UUID, draft: ShapeFieldDraft) {
        let target = state.selectedShapeId ?? fallbackShapeId
        guard let value = Int(draft.text.wrappedValue), var resolved = editingShape(target) else { return }
        let clamped = TextLayoutStyle.clampLineHeightMultiple(CGFloat(value) / 100.0)
        guard resolved.lineHeightMultiple != clamped || resolved.lineSpacing != nil else { return }
        resolved.lineHeightMultiple = clamped
        resolved.lineSpacing = nil
        RichTextUtils.syncShapeStyleIfNeeded(in: &resolved, property: .lineHeight)
        state.updateShapeContinuous(resolved)
    }

    func currentLineHeightString(for shapeId: UUID) -> String {
        guard let shape = editingShape(shapeId) else { return "\(Int(TextLayoutStyle.defaultLineHeightMultiple * 100))" }
        let font = NSFont.systemFont(
            ofSize: shape.fontSize ?? CanvasShapeModel.defaultFontSize,
            weight: nsFontWeight(shape.fontWeight ?? 400)
        )
        let multiple = TextLayoutStyle.effectiveLineHeightMultiple(
            lineHeightMultiple: shape.lineHeightMultiple,
            legacyLineSpacing: shape.lineSpacing,
            font: font
        )
        return "\(Int((multiple * 100).rounded()))"
    }

    func commitLineHeight(to shapeId: UUID?, draft: ShapeFieldDraft) {
        draft.isActive.wrappedValue = false
        guard let shapeId, var resolved = editingShape(shapeId) else { return }
        guard let value = Int(draft.text.wrappedValue) else {
            draft.text.wrappedValue = currentLineHeightString(for: shapeId)
            return
        }
        let clamped = TextLayoutStyle.clampLineHeightMultiple(CGFloat(value) / 100.0)
        if resolved.lineHeightMultiple != clamped || resolved.lineSpacing != nil {
            resolved.lineHeightMultiple = clamped
            resolved.lineSpacing = nil
            RichTextUtils.syncShapeStyleIfNeeded(in: &resolved, property: .lineHeight)
            state.updateShape(resolved)
        }
        draft.text.wrappedValue = "\(Int((clamped * 100).rounded()))"
    }

    func nsFontWeight(_ weight: Int) -> NSFont.Weight {
        CSSFontWeight(css: weight).platform
    }

    // MARK: - Opacity & rotation

    func currentOpacityString(for shapeId: UUID) -> String {
        guard let shape = editingShape(shapeId) else { return "100" }
        return "\(Int((shape.opacity * 100).rounded()))"
    }

    func commitOpacity(to shapeId: UUID?, draft: ShapeFieldDraft) {
        draft.isActive.wrappedValue = false
        guard let shapeId, var resolved = editingShape(shapeId) else { return }
        guard let value = Int(draft.text.wrappedValue) else {
            draft.text.wrappedValue = currentOpacityString(for: shapeId)
            return
        }
        let clamped = min(max(value, 0), 100)
        let newOpacity = Double(clamped) / 100.0
        if resolved.opacity != newOpacity {
            resolved.opacity = newOpacity
            state.updateShape(resolved)
        }
        draft.text.wrappedValue = "\(clamped)"
    }

    func currentRotationString(for shapeId: UUID) -> String {
        formatRotation(liveRotation(shapeId))
    }

    func formatRotation(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded.formatted(.number.precision(.fractionLength(0...1)))
    }

    func commitRotation(to shapeId: UUID?, draft: ShapeFieldDraft) {
        draft.isActive.wrappedValue = false
        guard let shapeId, var resolved = editingShape(shapeId) else { return }
        guard let value = draft.text.wrappedValue.localeTolerantDouble() else {
            draft.text.wrappedValue = currentRotationString(for: shapeId)
            return
        }
        let normalized = CanvasShapeModel.normalizedRotation(value)
        if resolved.rotation != normalized {
            resolved.rotation = normalized
            state.updateShape(resolved)
        }
        draft.text.wrappedValue = formatRotation(normalized)
    }

    /// Also rewrites the draft: a focused field would otherwise commit its stale text on blur and
    /// undo the reset.
    func resetRotation(shapeId: UUID, draft: ShapeFieldDraft) {
        guard var resolved = editingShape(shapeId) else { return }
        guard resolved.rotation != 0 else { return }
        resolved.rotation = 0
        state.updateShape(resolved)
        draft.text.wrappedValue = "0"
    }

    /// Rotation as the reader sees it, following the canvas rotate handle mid-gesture. Reads the
    /// session's rotation alone rather than `liveGeometryShape`: this runs inside a body, so going
    /// through `applied(to:)` would subscribe the rotation control to every translate and resize
    /// tick as well.
    func liveRotation(_ shapeId: UUID) -> Double {
        if let live = state.liveShapeGeometry.rotation(for: shapeId) { return live }
        return resolvedDocumentShape(shapeId)?.rotation ?? 0
    }

    // MARK: - Bindings

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

    /// Turning an outline on writes colour *and* width together (and off clears both), so this
    /// can't be expressed as a single key-path binding.
    func outlineEnabledBinding(_ shapeId: UUID) -> Binding<Bool> {
        Binding(
            get: { (resolvedDocumentShape(shapeId)?.outlineWidth ?? 0) > 0 },
            set: { enabled in
                guard var updated = editingShape(shapeId) else { return }
                updated.outlineColor = enabled ? CanvasShapeModel.defaultOutlineColor : nil
                updated.outlineWidth = enabled ? CanvasShapeModel.defaultOutlineWidth : nil
                state.updateShape(updated)
            }
        )
    }

    /// Reads and writes through `editingShape`, not `rows`: a continuous burst only lands in the
    /// document when it settles, so building a tick from `rows` would drop every earlier field of
    /// the same burst — pitch, then yaw, in one visit to the 3D popover.
    func shapeBinding<T>(_ shapeId: UUID, _ keyPath: WritableKeyPath<CanvasShapeModel, T>, continuous: Bool = false) -> Binding<T> where T: Sendable {
        Binding(
            get: {
                guard let shape = continuous ? editingShape(shapeId) : resolvedDocumentShape(shapeId) else {
                    return CanvasShapeModel.placeholder[keyPath: keyPath]
                }
                return shape[keyPath: keyPath]
            },
            set: { newValue in
                guard var resolved = editingShape(shapeId) else { return }
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
                guard let shape = continuous ? editingShape(shapeId) : resolvedDocumentShape(shapeId) else { return defaultValue }
                return shape[keyPath: keyPath] ?? defaultValue
            },
            set: { newValue in
                guard var resolved = editingShape(shapeId) else { return }
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
                guard let shape = resolvedDocumentShape(shapeId) else { return 400 }
                return CustomFontRegistry.controlState(for: shape)?.effectiveWeight ?? shape.fontWeight ?? 400
            },
            set: { newValue in
                guard var resolved = editingShape(shapeId) else { return }
                RichTextUtils.applyFontWeightUpdate(to: &resolved, weight: newValue)
                state.updateShape(resolved)
            }
        )
    }

    func italicBinding(_ shapeId: UUID) -> Binding<Bool> {
        Binding(
            get: {
                guard let shape = resolvedDocumentShape(shapeId) else { return false }
                return CustomFontRegistry.controlState(for: shape)?.effectiveItalic ?? shape.italic ?? false
            },
            set: { newValue in
                guard var resolved = editingShape(shapeId) else { return }
                RichTextUtils.applyItalicUpdate(to: &resolved, italic: newValue)
                state.updateShape(resolved)
            }
        )
    }

    func applyImportedFontSelection(_ imported: ImportedCustomFontSelection, to shapeId: UUID) {
        guard var resolved = editingShape(shapeId) else { return }
        RichTextUtils.applyImportedFontSelection(imported, to: &resolved, property: .fontName)
        state.updateShape(resolved)
    }

    func clearRichTextFormatting(_ shapeId: UUID) {
        guard var updated = editingShape(shapeId) else { return }
        updated.richText = nil
        state.updateShape(updated)
    }

    // MARK: - Text background

    func applyTextBackgroundPreset(_ preset: TextBackgroundPreset, shapeId: UUID) {
        guard var updated = editingShape(shapeId) else { return }
        updated.textBackgroundColor = preset.color
        updated.textBackgroundPadding = preset.padding
        updated.textBackgroundCornerRadius = preset.cornerRadius
        updated.textBackgroundOutlineColor = preset.outlineColor
        updated.textBackgroundOutlineWidth = preset.outlineWidth
        updated.textBackgroundOpacity = nil
        state.updateShape(updated)
    }

    /// Enable/disable toggles every field together against the live selection — same shape as the
    /// outline toggle. Background is a base-shape (non-localized) style, so writes land on base.
    func textBackgroundEnabledBinding(_ shapeId: UUID) -> Binding<Bool> {
        Binding(
            get: { resolvedDocumentShape(shapeId)?.textBackgroundColorData != nil },
            set: { enabled in
                guard var updated = editingShape(shapeId) else { return }
                updated.textBackgroundColor = enabled ? CanvasShapeModel.defaultTextBackgroundColor : nil
                updated.textBackgroundCornerRadius = enabled ? 0 : nil
                updated.textBackgroundPadding = enabled ? 0 : nil
                updated.textBackgroundOutlineColor = nil
                updated.textBackgroundOutlineWidth = nil
                updated.textBackgroundOpacity = nil
                state.updateShape(updated)
            }
        )
    }

    func textBackgroundOpacityPercentBinding(_ shapeId: UUID) -> Binding<CGFloat> {
        let opacity = shapeBinding(shapeId, \.textBackgroundOpacity, default: 1.0, continuous: true)
        return Binding(
            get: { CGFloat(opacity.wrappedValue * 100) },
            set: { opacity.wrappedValue = Double($0) / 100 }
        )
    }

    func textBackgroundOutlineEnabledBinding(_ shapeId: UUID) -> Binding<Bool> {
        Binding(
            get: { (resolvedDocumentShape(shapeId)?.textBackgroundOutlineWidth ?? 0) > 0 },
            set: { enabled in
                guard var updated = editingShape(shapeId) else { return }
                updated.textBackgroundOutlineColor = enabled ? CanvasShapeModel.defaultTextBackgroundOutlineColor : nil
                updated.textBackgroundOutlineWidth = enabled ? CanvasShapeModel.defaultTextBackgroundOutlineWidth : nil
                state.updateShape(updated)
            }
        )
    }
}

struct TextBackgroundPreset: Identifiable {
    let id = UUID()
    let name: String
    let color: Color
    let padding: CGFloat
    let cornerRadius: CGFloat
    let outlineColor: Color?
    let outlineWidth: CGFloat?

    // String(localized:) literals so the catalog extractor picks the names up (it can't see
    // LocalizedStringKey buried in a struct initializer). Button(_ String) renders them verbatim.
    static var presets: [TextBackgroundPreset] {
        [
            .init(name: String(localized: "Solid"), color: .black, padding: 16, cornerRadius: 8, outlineColor: nil, outlineWidth: nil),
            .init(name: String(localized: "Pill"), color: .black, padding: 20, cornerRadius: 100, outlineColor: nil, outlineWidth: nil),
            .init(name: String(localized: "Outline"), color: .white, padding: 16, cornerRadius: 8, outlineColor: .black, outlineWidth: 4),
            .init(name: String(localized: "Highlight"), color: .yellow.opacity(0.4), padding: 6, cornerRadius: 4, outlineColor: nil, outlineWidth: nil),
        ]
    }
}
