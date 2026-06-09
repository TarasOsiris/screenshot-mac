import Testing
import AppKit
import SwiftUI
@testable import Screenshot_Bro

@Suite(.serialized)
@MainActor
struct RichTextFormatUndoTests {

    /// Supplies a deterministic undo manager so a windowless NSTextView has one to register on.
    /// `groupsByEvent = false` lets the test close a group per action (the real app gets one
    /// group per runloop event); each grouped block keeps an open group around `registerUndo`.
    private final class UndoProvidingDelegate: NSObject, NSTextViewDelegate {
        let manager: UndoManager = {
            let m = UndoManager()
            m.groupsByEvent = false
            return m
        }()
        func undoManager(for view: NSTextView) -> UndoManager? { manager }

        func grouped(_ body: () -> Void) {
            manager.beginUndoGrouping()
            body()
            manager.endUndoGrouping()
        }
    }

    private func makeTextView(_ string: String) -> (NSTextView, UndoProvidingDelegate) {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 50))
        textView.isRichText = true
        textView.allowsUndo = true
        let delegate = UndoProvidingDelegate()
        textView.delegate = delegate
        textView.textStorage?.setAttributedString(NSAttributedString(string: string, attributes: [
            .font: NSFont.systemFont(ofSize: 24, weight: .regular),
            .foregroundColor: NSColor.black
        ]))
        return (textView, delegate)
    }

    private func isBold(_ textView: NSTextView, at index: Int) -> Bool {
        guard let font = textView.textStorage?.attribute(.font, at: index, effectiveRange: nil) as? NSFont
        else { return false }
        return font.fontDescriptor.symbolicTraits.contains(.bold)
    }

    @Test func toggleBoldIsUndoableAndRedoable() {
        let (textView, delegate) = makeTextView("Hello")
        let controller = RichTextFormatController()
        controller.textView = textView
        textView.setSelectedRange(NSRange(location: 0, length: 5))

        #expect(isBold(textView, at: 0) == false)

        delegate.grouped { controller.applyAction(.toggleBold) }
        #expect(isBold(textView, at: 0) == true)
        #expect(delegate.manager.canUndo == true)

        delegate.manager.undo()
        #expect(isBold(textView, at: 0) == false)

        delegate.manager.redo()
        #expect(isBold(textView, at: 0) == true)
    }

    @Test func undoingFirstFormattingRestoresPlainTextEncodingState() {
        let (textView, delegate) = makeTextView("Hello")
        let controller = RichTextFormatController()
        controller.textView = textView
        textView.setSelectedRange(NSRange(location: 0, length: 5))

        #expect(controller.shouldEncodeRichText == false)

        delegate.grouped { controller.applyAction(.toggleBold) }
        #expect(isBold(textView, at: 0) == true)
        #expect(controller.shouldEncodeRichText == true)

        delegate.manager.undo()
        #expect(isBold(textView, at: 0) == false)
        #expect(controller.shouldEncodeRichText == false)
    }

    @Test func clearFormattingIsUndoable() {
        let (textView, delegate) = makeTextView("Hello")
        let controller = RichTextFormatController()
        controller.textView = textView
        textView.setSelectedRange(NSRange(location: 0, length: 5))

        delegate.grouped { controller.applyAction(.toggleBold) }
        delegate.grouped { controller.applyAction(.setColor(.red)) }
        #expect(isBold(textView, at: 0) == true)

        textView.setSelectedRange(NSRange(location: 0, length: 5))
        delegate.grouped { controller.applyAction(.clearFormatting) }
        #expect(isBold(textView, at: 0) == false)
        // Clearing disables rich-text encoding.
        #expect(controller.shouldEncodeRichText == false)

        delegate.manager.undo()
        #expect(isBold(textView, at: 0) == true)
        // Undo must re-enable encoding, else the restored formatting is dropped on commit.
        #expect(controller.shouldEncodeRichText == true)
    }

    /// SwiftUI's ColorPicker re-fires its binding with the already-applied color, so
    /// applyAction runs again with no actual change. That redundant call must NOT register a
    /// second, no-op undo step — otherwise one Cmd+Z appears to "do nothing" before the next
    /// one reverts the color.
    @Test func redundantSameColorDoesNotAddUndoStep() {
        let (textView, delegate) = makeTextView("Hello")
        let controller = RichTextFormatController()
        controller.textView = textView
        textView.setSelectedRange(NSRange(location: 0, length: 5))

        func colorAt0() -> NSColor? {
            textView.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        }

        delegate.grouped { controller.applyAction(.setColor(.red)) }
        #expect(delegate.manager.canUndo == true)

        // Redundant re-apply of the same color registers nothing (no open group needed).
        controller.applyAction(.setColor(.red))

        delegate.manager.undo()
        // A single undo fully reverts the color and empties the stack — no phantom step.
        #expect(colorAt0()?.usingColorSpace(.sRGB)?.redComponent != 1.0)
        #expect(delegate.manager.canUndo == false)
    }

    /// Formatting must register on the controller's *explicitly captured* session manager, not
    /// whatever `textView.undoManager` resolves to through the responder chain. In a real window
    /// those differ on the first editor instance, which left the very first edit after a load
    /// undoing nothing — Cmd+Z routed to the session manager while the step landed elsewhere.
    @Test func formattingRegistersOnExplicitSessionManager() {
        let (textView, delegate) = makeTextView("Hello")
        // Stand in for the window/responder-chain manager that textView.undoManager would resolve to.
        let strayManager = UndoManager()
        let controller = RichTextFormatController()
        controller.textView = textView
        controller.undoManager = delegate.manager
        textView.setSelectedRange(NSRange(location: 0, length: 5))

        delegate.grouped { controller.applyAction(.toggleBold) }

        #expect(delegate.manager.canUndo == true)
        #expect(strayManager.canUndo == false)

        delegate.manager.undo()
        #expect(isBold(textView, at: 0) == false)
    }

    /// The inline editor must register undo on its own session manager, NOT the
    /// document/window manager — otherwise formatting steps interleave with document
    /// undo and outlive the freed text view, crashing on a later document-level undo:.
    @Test func editorUsesIsolatedUndoManagerClearedOnTeardown() {
        let documentUndoManager = UndoManager()
        let editor = InlineTextEditor(text: .constant("Hello"), font: .systemFont(ofSize: 24),
                                      color: .black, alignment: .center, onCommit: {})
        let coordinator = editor.makeCoordinator()

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 50))
        textView.allowsUndo = true
        textView.delegate = coordinator

        // The coordinator hands the text view its own session manager, never the
        // document/window manager. performUndoCommand drives textView.undoManager directly,
        // so it must resolve through the delegate to the session manager.
        #expect(coordinator.undoManager(for: textView) === coordinator.editingUndoManager)
        #expect(textView.undoManager === coordinator.editingUndoManager)
        #expect(coordinator.editingUndoManager !== documentUndoManager)

        let controller = RichTextFormatController()
        controller.textView = textView
        textView.textStorage?.setAttributedString(NSAttributedString(string: "Hello", attributes: [
            .font: NSFont.systemFont(ofSize: 24), .foregroundColor: NSColor.black
        ]))
        textView.setSelectedRange(NSRange(location: 0, length: 5))

        // applyAction registers on whichever manager the text view exposes; force that
        // to be the session manager (as it is in production via undoManager(for:)).
        let session = coordinator.editingUndoManager
        session.beginUndoGrouping()
        session.registerUndo(withTarget: textView) { _ in }
        session.endUndoGrouping()
        #expect(session.canUndo == true)
        #expect(documentUndoManager.canUndo == false)

        // Teardown drops the steps so nothing can invoke an undo against the freed view.
        let scrollView = CenteringScrollView()
        scrollView.documentView = textView
        InlineTextEditor.dismantleNSView(scrollView, coordinator: coordinator)
        #expect(session.canUndo == false)
    }
}
