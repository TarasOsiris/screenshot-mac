import Foundation
@testable import Screenshot_Bro
import Testing

@MainActor
struct TranslationLineBreakTests {
    private static func isSentinel(_ scalar: Unicode.Scalar) -> Bool {
        lineBreakSentinelRange.contains(scalar.value)
    }

    @Test(arguments: [
        "Line one\nLine two",
        "Padded  \n  line",
        "Windows\r\nbreak",
        "Blank\n\nline between",
        "Whitespace-only\n  \nline between",
        "Trailing break\n",
        "\nLeading break",
        "Three\nshort\nlines",
        "Icon font \u{E000} and \u{E001}\nglyphs survive",
    ])
    func identityTranslationRestoresTheOriginalExactly(_ text: String) async throws {
        let result = try await translatePreservingLineBreaks(text) { $0 }
        #expect(result == text)
    }

    /// No newline, or more breaks than there are free sentinels: nothing to protect.
    @Test(arguments: [
        "Hello  world ",
        String(repeating: "a\n", count: lineBreakSentinelRange.count + 1),
    ])
    func textIsSentUntouched(_ text: String) async throws {
        var sent: [String] = []
        let result = try await translatePreservingLineBreaks(text) { request in
            sent.append(request)
            return request
        }
        #expect(sent == [text])
        #expect(result == text)
    }

    @Test func multilineTextIsTranslatedInOneRequest() async throws {
        var requests = 0
        let result = try await translatePreservingLineBreaks("hello\nworld") { text in
            requests += 1
            return text.uppercased()
        }
        #expect(requests == 1)
        #expect(result == "HELLO\nWORLD")
    }

    /// The engine pads around tokens it doesn't recognize; that padding must not survive.
    @Test func paddingTheTranslatorAddsAroundSentinelsIsDropped() async throws {
        let result = try await translatePreservingLineBreaks("one\ntwo") { text in
            text.unicodeScalars.map { Self.isSentinel($0) ? "   \($0)   " : String($0) }.joined()
        }
        #expect(result == "one\ntwo")
    }

    @Test func droppedSentinelLeavesTheOtherBreaksRestored() async throws {
        let result = try await translatePreservingLineBreaks("one\ntwo\nthree") { text in
            var dropped = text
            if let first = dropped.unicodeScalars.firstIndex(where: Self.isSentinel) {
                dropped.unicodeScalars.remove(at: first)
            }
            return dropped
        }
        #expect(!result.unicodeScalars.contains(where: Self.isSentinel))
        #expect(result.hasSuffix("two\nthree"))
        #expect(result.contains("one"))
    }

    @Test func duplicatedSentinelIsRestoredNotLeaked() async throws {
        let result = try await translatePreservingLineBreaks("one\ntwo") { text in
            text + text
        }
        #expect(result == "one\ntwoone\ntwo")
    }
}
