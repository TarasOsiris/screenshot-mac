import Foundation
@testable import Screenshot_Bro
import Testing

struct NSRangeExtensionTests {

    @Test(arguments: [
        (NSRange(location: 1, length: 2), 5, NSRange(location: 1, length: 2)),
        (NSRange(location: 0, length: 5), 5, NSRange(location: 0, length: 5)),
        (NSRange(location: 3, length: 10), 5, NSRange(location: 3, length: 2)),
        (NSRange(location: 5, length: 0), 5, NSRange(location: 5, length: 0)),
        (NSRange(location: 5, length: 3), 5, NSRange(location: 5, length: 0)),
        (NSRange(location: 9, length: 4), 5, NSRange(location: 5, length: 0)),
        (NSRange(location: NSNotFound, length: 0), 5, NSRange(location: 5, length: 0)),
        (NSRange(location: 2, length: 4), 0, NSRange(location: 0, length: 0)),
    ])
    func clampedStaysInsideText(range: NSRange, length: Int, expected: NSRange) {
        #expect(range.clamped(toLength: length) == expected)
    }

    @Test func uppercasingKeepsAsciiSelection() {
        #expect(NSRange(location: 2, length: 3).mappedThroughUppercasing("hello world") == NSRange(location: 2, length: 3))
    }

    @Test func uppercasingShiftsCaretPastExpandedCharacter() {
        // "straße" → "STRASSE": the caret after "ß" moves one unit right.
        #expect(NSRange(location: 5, length: 0).mappedThroughUppercasing("straße") == NSRange(location: 6, length: 0))
    }

    @Test func uppercasingGrowsSelectionOverExpandedCharacter() {
        #expect(NSRange(location: 4, length: 1).mappedThroughUppercasing("straße") == NSRange(location: 4, length: 2))
    }

    @Test func uppercasingClampsStaleSelection() {
        #expect(NSRange(location: 8, length: 2).mappedThroughUppercasing("abc") == NSRange(location: 3, length: 0))
    }
}
