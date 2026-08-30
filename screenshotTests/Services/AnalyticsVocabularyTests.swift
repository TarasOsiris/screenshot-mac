import Foundation
@testable import Screenshot_Bro
import Testing

/// Pins the vocabularies the 4.9 instrumentation fixes introduced. Each of these existed as a bug
/// before it existed as a test: `platform` reported every iPhone as an iPad, `screenshots_imported`
/// fired on one of eleven import paths, `onboarding_skipped` could not fire at all, and
/// `store_upload_failed` carried no reason.
@Suite(.serialized)
struct AnalyticsVocabularyTests {

    /// Every value that reaches a `.result` / `.source` key must survive `beforeSend`, which drops
    /// any string on a key outside the allowlist. Raw-value uniqueness is not asserted — Swift
    /// rejects duplicate raw values at compile time.
    private func expectWireSafe(_ raw: [String], key: String, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(raw.allSatisfy { !$0.isEmpty }, sourceLocation: sourceLocation)
        #expect(
            raw.allSatisfy { AnalyticsService.allowsProperty(key: key, value: $0) },
            "\(key) drops one of \(raw)",
            sourceLocation: sourceLocation
        )
    }

    // MARK: - Platform

    /// The whole point of the fix: iPhone must be reportable as something other than iPad.
    @Test func platformCanDistinguishIPhoneFromIPad() {
        let raw = PlatformDeviceClass.allCases.map(\.rawValue)
        expectWireSafe(raw, key: "platform")
        #expect(Set(raw).isSuperset(of: ["iphone", "ipados", "macos"]))
    }

    // MARK: - Image import origin

    @Test func importOriginsAreWireSafe() {
        expectWireSafe(ImageImportOrigin.allCases.map(\.rawValue), key: "source")
    }

    // MARK: - Onboarding outcomes

    /// The assertion that would have caught the original bug: `end()` defaulted to "completed",
    /// so every abandonment was counted as a completion and `onboarding_skipped` never fired.
    /// `started` only reconciles against `completed + skipped` if both remain reachable.
    @Test func onboardingOutcomesReachBothTerminalEvents() {
        expectWireSafe(OnboardingOutcome.allCases.map(\.rawValue), key: "result")
        let abandonments: [OnboardingOutcome] = [.skipped, .dismissed, .interrupted]
        let completions: [OnboardingOutcome] = [.finished, .pro]
        #expect(Set(abandonments + completions) == Set(OnboardingOutcome.allCases))
    }

    // MARK: - Store upload failure classification

    @Test func uploadFailureKindsAreWireSafe() {
        expectWireSafe(StoreUploadFailureKind.allCases.map(\.rawValue), key: "result")
    }

    /// The store error enums carry `rowLabel`, `localeLabel` and `fileNames` as associated values,
    /// so each of these must classify by *shape* — and land on a specific kind, not the `.unknown`
    /// catch-all, which is how a bucket starts absorbing everything.
    @Test func classificationReadsShapeNotContent() {
        let cases: [(Error, StoreUploadFailureKind)] = [
            (GooglePlayUploadError.renderFailed(
                rowLabel: "Secret Row", imageTypeLabel: "phone", languageLabel: "Klingon", index: 0
            ), .renderFailed),
            (GooglePlayUploadError.unreadableImages(
                rowLabel: "Secret Row", languageLabel: "Klingon", fileNames: ["private.png"]
            ), .unreadableImages),
            (AppStoreConnectUploadError.renderFailed(
                rowLabel: "Secret Row", displayTypeLabel: "APP_IPHONE_67", localeLabel: "Klingon", index: 0
            ), .renderFailed),
            (ASCScreenshotSyncError.unreadableImages(
                rowLabel: "Secret Row", localeLabel: "Klingon", fileNames: ["private.png"]
            ), .unreadableImages),
            (ASCScreenshotSyncError.invalidPlan("Secret Row"), .stalePlan),
            (ASCScreenshotSyncError.planExpired, .stalePlan),
            (GooglePlayUploadError.noRowsSelected, .nothingSelected),
            (CancellationError(), .cancelled),
            (URLError(.notConnectedToInternet), .transport),
            (GooglePlayAPIError.decodingFailed(CancellationError()), .decodingFailed),
            (AppStoreConnectAuthError.missingIssuerId, .auth),
        ]
        for (error, expected) in cases {
            #expect(StoreUploadFailure.classify(error).kind == expected, "\(expected.rawValue) misclassified")
        }
    }

    @Test func classificationExtractsTheStoreStatusCode() {
        #expect(StoreUploadFailure.classify(GooglePlayAPIError.httpError(status: 429, message: "slow down"))
            == StoreUploadFailure(kind: .httpError, errorCode: 429))
        #expect(StoreUploadFailure.classify(AppStoreConnectAPIError.httpError(status: 409, message: "conflict"))
            == StoreUploadFailure(kind: .httpError, errorCode: 409))
    }

    /// A status code is safe to send; the API message that came with it is not.
    @Test func errorCodeCannotCarryAString() {
        #expect(AnalyticsService.allowsProperty(key: "error_code", value: "Internal Server Error") == false)
    }

    // MARK: - Restore and translation results

    @Test func restoreResultsAreWireSafe() {
        expectWireSafe(StoreService.RestoreResult.allCases.map(\.rawValue), key: "result")
    }

    /// `languagesNotDownloaded` used to absorb every failure — a declined download, a network
    /// fault and a mid-run shape error alike — which is why 5 of 6 production runs reported it.
    /// Its raw value is deliberately unchanged so the narrowed bucket stays comparable.
    @Test func translationResultsSeparateTheFailureModes() {
        expectWireSafe(TranslationRunResult.allCases.map(\.rawValue), key: "result")
        #expect(TranslationRunResult.languagesNotDownloaded.rawValue == "languagesNotDownloaded")
    }

    /// Every non-success result must reach the user as an alert, and every recoverable one must
    /// offer the retry — a silent or dead-ended failure is how the translation wall went
    /// unreported for three releases.
    @Test func everyTranslationFailureProducesAnActionableIssue() {
        #expect(TranslationLanguageIssue(.completed, language: "German") == nil)
        for result in TranslationRunResult.allCases where result != .completed {
            let issue = TranslationLanguageIssue(result, language: "German")
            #expect(issue != nil, "\(result.rawValue) has no alert")
            #expect(issue?.offersRetry == (result != .unsupportedPair), "\(result.rawValue) retry is wrong")
        }
    }
}
