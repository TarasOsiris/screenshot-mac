import AppKit
import CoreGraphics
import Foundation
@testable import Screenshot_Bro
import SwiftUI
import Testing

/// The multi-selection half of the shared editing layer, called by both the properties bar and
/// the selection inspector. Every write fans out to the selection; reads show the first shape.
@Suite(.serialized)
@MainActor
struct MultiShapeEditingTests {
    private struct Editor: MultiShapeEditing {
        let state: AppState
    }

    private func makeEditor(adding shapes: [CanvasShapeModel]) -> (AppState, URL, Editor, UndoManager) {
        let (state, tempDir) = makeTestState()
        state.selectRow(state.rows.first!.id)
        for shape in shapes { state.addShape(shape) }
        state.selectedShapeIds = Set(shapes.map(\.id))
        let undoManager = state.undoManager!
        undoManager.removeAllActions()
        return (state, tempDir, Editor(state: state), undoManager)
    }

    private func documentShape(_ state: AppState, _ id: UUID) -> CanvasShapeModel? {
        state.rows.first?.shapes.first { $0.id == id }
    }

    private func mixedColorRichText() -> String {
        let attributed = NSMutableAttributedString(string: "Hello", attributes: [
            .font: NSFont.systemFont(ofSize: 24, weight: .regular),
            .foregroundColor: NSColor.systemBlue
        ])
        attributed.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: NSRange(location: 3, length: 2))
        return RichTextUtils.encode(attributed) ?? ""
    }

    private func runColorCount(_ base64RTF: String?) -> Int {
        guard let decoded = RichTextUtils.decode(base64RTF ?? "") else { return 0 }
        var count = 0
        decoded.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: decoded.length)) { _, _, _ in
            count += 1
        }
        return count
    }

    private func textShape(_ color: Color, richText: String? = nil) -> CanvasShapeModel {
        var shape = CanvasShapeModel(type: .text, text: "Hello")
        shape.color = color
        shape.richText = richText
        return shape
    }

    @Test func multiTextColorBindingFansOutToEverySelectedTextShape() {
        let rich = textShape(.blue, richText: mixedColorRichText())
        let plain = textShape(.blue)
        let (state, tempDir, editor, _) = makeEditor(adding: [rich, plain])
        defer { cleanupTestState(tempDir) }

        editor.multiTextColorBinding().wrappedValue = .red

        #expect(documentShape(state, rich.id)?.colorData == CodableColor(.red))
        #expect(documentShape(state, plain.id)?.colorData == CodableColor(.red))
        #expect(runColorCount(documentShape(state, rich.id)?.richText) == 1)
        #expect(documentShape(state, plain.id)?.richText == nil)
    }

    @Test func multiTextColorBindingReadsTheFirstSelectedShape() {
        let first = textShape(.blue)
        let second = textShape(.green)
        let (_, tempDir, editor, _) = makeEditor(adding: [first, second])
        defer { cleanupTestState(tempDir) }

        #expect(CodableColor(editor.multiTextColorBinding().wrappedValue) == CodableColor(.blue))
    }

    @Test func multiTextColorBindingIsOneUndoStep() {
        let first = textShape(.blue)
        let second = textShape(.blue)
        let (state, tempDir, editor, undoManager) = makeEditor(adding: [first, second])
        defer { cleanupTestState(tempDir) }

        editor.multiTextColorBinding().wrappedValue = .red

        #expect(undoManager.canUndo)
        undoManager.undo()
        #expect(documentShape(state, first.id)?.colorData == CodableColor(.blue))
        #expect(documentShape(state, second.id)?.colorData == CodableColor(.blue))
        #expect(!undoManager.canUndo)
    }

    /// Writing back the value the binding just handed out must change nothing — otherwise a
    /// ColorPicker reprogramming itself would flatten every selected shape's per-run colors.
    @Test func multiTextColorBindingNoOpWriteRegistersNoUndoStep() {
        let rich = textShape(.red, richText: mixedColorRichText())
        let plain = textShape(.red)
        let (state, tempDir, editor, undoManager) = makeEditor(adding: [rich, plain])
        defer { cleanupTestState(tempDir) }

        let binding = editor.multiTextColorBinding()
        binding.wrappedValue = binding.wrappedValue

        #expect(!undoManager.canUndo)
        #expect(documentShape(state, rich.id)?.richText == rich.richText)
        #expect(runColorCount(documentShape(state, rich.id)?.richText) == 2)
    }

    /// Color is not locale-overridable, so it always lands on the base shape. The rich-text sync
    /// it triggers *is*, so the recolored RTF lands as an override and the base keeps its old
    /// colors — the same split the single-shape path has always produced.
    @Test func multiTextColorBindingWritesColorToTheBaseShapeInANonBaseLocale() throws {
        let rich = textShape(.blue, richText: mixedColorRichText())
        let (state, tempDir, editor, _) = makeEditor(adding: [rich])
        defer { cleanupTestState(tempDir) }
        state.addLocale(.init(code: "fr", label: "French"))
        state.setActiveLocale("fr")
        state.selectedShapeIds = [rich.id]

        editor.multiTextColorBinding().wrappedValue = .red

        let base = try #require(documentShape(state, rich.id))
        #expect(base.colorData == CodableColor(.red), "Color applies to every locale")
        #expect(base.richText == rich.richText, "The base RTF is left alone")

        let resolved = LocaleService.resolveShape(base, localeState: state.localeState)
        #expect(runColorCount(resolved.richText) == 1, "The active locale carries the recolored RTF")
    }
}
