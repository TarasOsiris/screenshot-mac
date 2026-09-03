#if os(macOS)
import AppKit
@testable import Screenshot_Bro
import Testing

@MainActor
struct CommitTextViewTests {

    /// Pins the fix for Sentry SCREENSHOT-BRO-1D: with Writing Tools on, the affordance is
    /// scheduled against a view SwiftUI tears down on commit, and clicking it presents a popover
    /// against a window-less view. Also proves the plain `CommitTextView()` initializer reaches
    /// the override that sets this.
    @Test func writingToolsAreDisabled() {
        #expect(CommitTextView().writingToolsBehavior == NSWritingToolsBehavior.none)
    }

    @Test func leavingItsWindowCollapsesTheSelection() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        let textView = CommitTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        window.contentView?.addSubview(textView)
        textView.string = "Ship it"
        textView.selectAll(nil)
        #expect(textView.selectedRange().length > 0)

        textView.removeFromSuperview()

        #expect(textView.selectedRange().length == 0)
        #expect(textView.window == nil)
    }
}
#endif
