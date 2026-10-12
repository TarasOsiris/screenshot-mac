#if os(macOS)
import AppKit
@testable import Screenshot_Bro
import SwiftUI
import Testing

/// SCREENSHOT-BRO-2F: SwiftUI's `TextEditor` left its typing steps on the window's undo stack after
/// it was freed, and ⌘Z in a later text field replayed one on the dead text view.
@Suite(.serialized)
@MainActor
struct PlainTextEditorTests {
    private final class TextBox {
        var value: String
        init(_ value: String) { self.value = value }
    }

    private struct Harness {
        let window: NSWindow
        let hosting: NSHostingView<AnyView>
        let textView: NSTextView
        let box: TextBox

        func rerender(showingEditor: Bool = true) {
            hosting.rootView = PlainTextEditorTests.root(box, showingEditor: showingEditor)
            hosting.layoutSubtreeIfNeeded()
        }

        func type(_ string: String) {
            window.makeFirstResponder(textView)
            textView.insertText(string, replacementRange: NSRange(location: textView.string.utf16.count, length: 0))
        }
    }

    private static func root(_ box: TextBox, showingEditor: Bool) -> AnyView {
        let text = Binding(get: { box.value }, set: { box.value = $0 })
        return AnyView(VStack {
            if showingEditor {
                PlainTextEditor(text: text, font: .systemFont(ofSize: 12))
            }
        }.frame(width: 300, height: 120))
    }

    private func makeHarness(_ initial: String) throws -> Harness {
        let box = TextBox(initial)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 120),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: Self.root(box, showingEditor: true))
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        let textView = try #require(Self.textViews(in: hosting).first)
        return Harness(window: window, hosting: hosting, textView: textView, box: box)
    }

    private static func textViews(in view: NSView) -> [NSTextView] {
        (view as? NSTextView).map { [$0] } ?? view.subviews.flatMap(textViews)
    }

    /// Lets the run loop close the typing's event undo group.
    private func endEvent() async throws {
        try await Task.sleep(for: .milliseconds(50))
    }

    @Test func typingUndoesOnTheEditorsOwnStack() async throws {
        let harness = try makeHarness("Hello")
        defer { harness.window.close() }
        harness.type(" world")
        #expect(harness.box.value == "Hello world")

        let manager = try #require(harness.textView.undoManager)
        #expect(manager !== harness.window.undoManager)
        #expect(harness.window.undoManager?.canUndo != true)

        try await endEvent()
        manager.undo()
        #expect(harness.textView.string == "Hello")
        // AppKit sends no textDidChange for undo; the binding must follow anyway.
        #expect(harness.box.value == "Hello")
    }

    @Test func tearingDownTheEditorDropsItsSteps() async throws {
        let harness = try makeHarness("Hello")
        defer { harness.window.close() }
        harness.type("!")
        let manager = try #require(harness.textView.undoManager)
        try await endEvent()
        #expect(manager.canUndo)

        harness.rerender(showingEditor: false)
        #expect(Self.textViews(in: harness.hosting).isEmpty)
        #expect(!manager.canUndo)
    }

    @Test func anOutsideWriteReplacesTheTextAndItsUndoHistory() async throws {
        let harness = try makeHarness("Hello")
        defer { harness.window.close() }
        harness.type("!")
        try await endEvent()

        harness.box.value = "Bonjour"
        harness.rerender()
        #expect(harness.textView.string == "Bonjour")
        #expect(harness.textView.undoManager?.canUndo != true)
    }
}
#endif
