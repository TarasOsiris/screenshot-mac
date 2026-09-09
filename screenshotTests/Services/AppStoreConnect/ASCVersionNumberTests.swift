import Foundation
@testable import Screenshot_Bro
import Testing

// The wizard prefills the next version number for the user to accept. Getting it wrong creates a
// version record in App Store Connect they then have to clean up, so the arithmetic is pinned.
struct ASCVersionNumberTests {

    @Test func theLastComponentIsIncremented() {
        #expect(ASCVersionNumber.next(after: "4.14") == "4.15")
        #expect(ASCVersionNumber.next(after: "1.2.3") == "1.2.4")
        #expect(ASCVersionNumber.next(after: "4") == "5")
        #expect(ASCVersionNumber.next(after: "1.9") == "1.10", "no carry — Apple has no 1.10 problem")
    }

    /// Apple accepts at most three numeric components, so anything else is someone else's format
    /// and a bump built from it would be rejected.
    @Test func anythingNotDottedNumericHasNoSuggestion() {
        for input in ["", "4.15-beta", "v4.15", "4.1.2.3", "4..1", "-1", "4.x"] {
            #expect(ASCVersionNumber.next(after: input) == nil, "\(input)")
        }
    }

    /// Plain string ordering would make 4.9 the highest of the two.
    @Test func highestComparesComponentsNumerically() {
        #expect(ASCVersionNumber.highest(of: ["4.9", "4.14", "4.10"]) == "4.14")
        #expect(ASCVersionNumber.highest(of: ["1.0", "10.0", "2.0"]) == "10.0")
        #expect(ASCVersionNumber.highest(of: []) == nil)
    }
}
