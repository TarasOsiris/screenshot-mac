import Foundation
@testable import Screenshot_Bro
import Testing

@MainActor
struct TranslationLineBreakTests {
    private static let privateUseArea: ClosedRange<UInt32> = 0xE000...0xF8FF

    private func containsSentinel(_ text: String) -> Bool {
        text.unicodeScalars.contains { Self.privateUseArea.contains($0.value) }
    }

    @Test(arguments: [
        "Line one\nLine two",
        "Padded  \n  line",
        "Windows\r\nbreak",
        "Blank\n\nline between",
        "Trailing break\n",
        "\nLeading break",
        "Three\nshort\nlines",
    ])
    func identityTranslationRestoresTheOriginalExactly(_ text: String) async throws {
        let result = try await translatePreservingLineBreaks(text) { $0 }
        #expect(result == text)
    }

    @Test func textWithoutNewlinesIsSentUntouched() async throws {
        var sent: [String] = []
        let result = try await translatePreservingLineBreaks("Hello  world ") { text in
            sent.append(text)
            return text
        }
        #expect(sent == ["Hello  world "])
        #expect(result == "Hello  world ")
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
            text.unicodeScalars.map { scalar in
                Self.privateUseArea.contains(scalar.value) ? "   \(scalar)   " : String(scalar)
            }.joined()
        }
        #expect(result == "one\ntwo")
    }

    @Test func droppedSentinelNeverLeaksIntoTheResult() async throws {
        let result = try await translatePreservingLineBreaks("one\ntwo") { text in
            String(String.UnicodeScalarView(text.unicodeScalars.filter { !Self.privateUseArea.contains($0.value) }))
        }
        #expect(!containsSentinel(result))
        #expect(result.contains("one"))
        #expect(result.contains("two"))
    }
}
