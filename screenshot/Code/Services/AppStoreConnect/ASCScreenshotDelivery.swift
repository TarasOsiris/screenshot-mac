import Foundation

/// What App Store Connect reported about one uploaded screenshot once it stopped processing.
///
/// `waitForDelivery` is the only place the app ever sees `ASCAssetDeliveryState`, and it used to
/// flatten it into a thrown string. Returning it instead is what lets an agent confirm an upload
/// landed from the tool result alone, rather than polling the `asc` CLI out of band.
nonisolated struct ASCScreenshotDeliveryOutcome: Sendable {
    let screenshotId: String
    /// Apple's raw state, e.g. `COMPLETE`. Not user content.
    let state: String
    /// Apple's own warning text. Not user content.
    let messages: [String]

    var isComplete: Bool { state.caseInsensitiveCompare("COMPLETE") == .orderedSame }

    /// Assets already live on the store aren't re-fetched just to learn what we already know.
    static func assumedComplete(_ screenshotId: String) -> ASCScreenshotDeliveryOutcome {
        ASCScreenshotDeliveryOutcome(screenshotId: screenshotId, state: "COMPLETE", messages: [])
    }
}

/// A delivery that did not reach `COMPLETE`, surfaced per set so the happy path can stay a
/// histogram rather than an array of identical strings.
nonisolated struct ASCScreenshotDeliveryProblem: Encodable, Sendable {
    let screenshotId: String
    let state: String
    let messages: [String]
}
