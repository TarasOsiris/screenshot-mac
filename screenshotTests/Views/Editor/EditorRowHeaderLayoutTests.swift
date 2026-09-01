#if os(macOS)
import AppKit
#else
import UIKit
#endif
import CoreGraphics
import Foundation
@testable import Screenshot_Bro
import Testing

@MainActor
struct EditorRowHeaderLayoutTests {

    private var chrome: CGFloat { EditorRowHeaderLayout.fixedChromeWidth }

    @Test func showsLabelsBeforeTheViewportHasBeenMeasured() {
        // Zero is "not measured yet" — showing the labels avoids a flash of the compact layout.
        #expect(EditorRowHeaderLayout.showsLabels(availableWidth: 0, labelsWidth: 9_999))
    }

    @Test func showsLabelsWhenThereIsRoomForThem() {
        #expect(EditorRowHeaderLayout.showsLabels(availableWidth: chrome + 200, labelsWidth: 120))
    }

    @Test func hidesLabelsWhenTheyWouldNotFit() {
        #expect(!EditorRowHeaderLayout.showsLabels(availableWidth: chrome + 100, labelsWidth: 200))
    }

    @Test func hidesLabelsWhenOnlyTheChromeFits() {
        #expect(!EditorRowHeaderLayout.showsLabels(availableWidth: chrome, labelsWidth: 1))
    }

    @Test func keepsAMarginSoFixedSizeLabelsCannotOverflow() {
        // Exactly filling the leftover space must still hide: the labels are `fixedSize` and would
        // push the trailing controls off the row rather than compress.
        let leftover: CGFloat = 100
        #expect(!EditorRowHeaderLayout.showsLabels(availableWidth: chrome + leftover, labelsWidth: leftover))
        #expect(EditorRowHeaderLayout.showsLabels(availableWidth: chrome + leftover, labelsWidth: leftover - 8))
    }

    @Test func measuresWiderTextAsWider() {
        let short = EditorRowHeaderLayout.textWidth("Hi", size: 12, weight: .medium)
        let long = EditorRowHeaderLayout.textWidth("A considerably longer row label", size: 12, weight: .medium)
        #expect(short > 0)
        #expect(long > short)
    }

    @Test func measuresAnEmptyStringAsZero() {
        #expect(EditorRowHeaderLayout.textWidth("", size: 12, weight: .medium) == 0)
    }
}
