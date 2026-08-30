import Foundation
@testable import Screenshot_Bro
import Testing

/// Pins the vocabularies the 4.9 instrumentation fixes introduced. Each of these existed as a bug
/// before it existed as a test: `platform` reported every iPhone as an iPad, `screenshots_imported`
/// fired on one of eleven import paths, `onboarding_skipped` could not fire at all, and
/// `store_upload_failed` carried no reason.
@Suite(.serialized)
struct AnalyticsVocabularyTests {

    // MARK: - Platform

    @Test func platformValuesAreDistinctSnakeCaseAndAllowlisted() {
        let raw = PlatformDeviceClass.allCases.map(\.rawValue)
        #expect(Set(raw).count == raw.count)
        #expect(raw.allSatisfy { $0.allSatisfy { $0.isLowercase || $0 == "_" } })
        #expect(raw.allSatisfy { AnalyticsService.allowsProperty(key: "platform", value: $0) })
    }

    /// The whole point of the fix: iPhone must be reportable as something other than iPad.
    @Test func platformCanDistinguishIPhoneFromIPad() {
        let raw = Set(PlatformDeviceClass.allCases.map(\.rawValue))
        #expect(raw.contains("iphone"))
        #expect(raw.contains("ipados"))
    }

    @MainActor @Test func platformMatchesTheRunningTarget() {
        #if os(macOS)
        #expect(PlatformDeviceClass.current == .macos)
        #else
        #expect(PlatformDeviceClass.current != .macos)
        #endif
    }

    // MARK: - Image import origin

    @Test func importOriginsAreDistinctSnakeCaseAndAllowlisted() {
        let raw = ImageImportOrigin.allCases.map(\.rawValue)
        #expect(raw.allSatisfy { !$0.isEmpty })
        #expect(Set(raw).count == raw.count)
        #expect(raw.allSatisfy { $0.allSatisfy { $0.isLowercase || $0 == "_" } })
        #expect(raw.allSatisfy { AnalyticsService.allowsProperty(key: "source", value: $0) })
    }

    // MARK: - Onboarding outcomes

    /// The assertion that would have caught the original bug: `end()` defaulted to "completed",
    /// so every abandonment was counted as a completion and `onboarding_skipped` never fired.
    @Test func everyOnboardingOutcomeMapsToATerminalEvent() {
        let events = Set(OnboardingOutcome.allCases.map(\.analyticsEvent))
        #expect(events == [.onboardingCompleted, .onboardingSkipped])
        #expect(OnboardingOutcome.dismissed.analyticsEvent == .onboardingSkipped)
        #expect(OnboardingOutcome.skipped.analyticsEvent == .onboardingSkipped)
        #expect(OnboardingOutcome.interrupted.analyticsEvent == .onboardingSkipped)
        #expect(OnboardingOutcome.pro.analyticsEvent == .onboardingCompleted)
        #expect(OnboardingOutcome.finished.analyticsEvent == .onboardingCompleted)
    }

    @Test func onboardingOutcomesAreDistinctAndAllowlisted() {
        let raw = OnboardingOutcome.allCases.map(\.rawValue)
        #expect(Set(raw).count == raw.count)
        #expect(raw.allSatisfy { AnalyticsService.allowsProperty(key: "result", value: $0) })
    }

    // MARK: - Store upload failure classification

    @Test func uploadFailureKindsAreDistinctSnakeCaseAndAllowlisted() {
        let raw = StoreUploadFailureKind.allCases.map(\.rawValue)
        #expect(Set(raw).count == raw.count)
        #expect(raw.allSatisfy { $0.allSatisfy { $0.isLowercase || $0 == "_" } })
        #expect(raw.allSatisfy { AnalyticsService.allowsProperty(key: "result", value: $0) })
    }

    /// The store error enums carry `rowLabel`, `localeLabel` and `fileNames` as associated values.
    /// The classifier must read the error's shape and transmit none of them.
    @Test func classificationLeaksNoUserContent() {
        let secrets = ["Secret Row", "Confidential Locale", "private-screenshot.png"]
        let errors: [Error] = [
            GooglePlayUploadError.renderFailed(
                rowLabel: secrets[0], imageTypeLabel: "phone", languageLabel: secrets[1], index: 0
            ),
            GooglePlayUploadError.unreadableImages(
                rowLabel: secrets[0], languageLabel: secrets[1], fileNames: [secrets[2]]
            ),
            AppStoreConnectUploadError.renderFailed(
                rowLabel: secrets[0], displayTypeLabel: "APP_IPHONE_67", localeLabel: secrets[1], index: 0
            ),
            ASCScreenshotSyncError.unreadableImages(
                rowLabel: secrets[0], localeLabel: secrets[1], fileNames: [secrets[2]]
            ),
            ASCScreenshotSyncError.invalidPlan(secrets[0]),
        ]
        for error in errors {
            let value = StoreUploadFailureKind.classify(error).kind.rawValue
            for secret in secrets {
                #expect(!value.localizedCaseInsensitiveContains(secret), "\(value) leaked \(secret)")
            }
        }
    }

    @Test func classificationExtractsHTTPStatusAndKind() {
        let http = StoreUploadFailureKind.classify(GooglePlayAPIError.httpError(status: 429, message: "slow down"))
        #expect(http.kind == .httpError)
        #expect(http.httpStatus == 429)

        let asc = StoreUploadFailureKind.classify(AppStoreConnectAPIError.httpError(status: 409, message: "conflict"))
        #expect(asc.kind == .httpError)
        #expect(asc.httpStatus == 409)

        #expect(StoreUploadFailureKind.classify(CancellationError()).kind == .cancelled)
        #expect(StoreUploadFailureKind.classify(ASCScreenshotSyncError.planExpired).kind == .stalePlan)
        #expect(StoreUploadFailureKind.classify(GooglePlayUploadError.noRowsSelected).kind == .nothingSelected)
        #expect(StoreUploadFailureKind.classify(GooglePlayAPIError.decodingFailed(CancellationError())).kind == .decodingFailed)
        #expect(StoreUploadFailureKind.classify(URLError(.notConnectedToInternet)).kind == .transport)
    }

    /// An HTTP status is safe to send; the API message that came with it is not. `http_status`
    /// must therefore stay out of the string allowlist.
    @Test func httpStatusCannotCarryAString() {
        #expect(AnalyticsService.allowsProperty(key: "http_status", value: 500))
        #expect(AnalyticsService.allowsProperty(key: "http_status", value: "Internal Server Error") == false)
    }

    // MARK: - Restore and translation results

    @Test func restoreResultsAreDistinctAndAllowlisted() {
        let raw: [String] = [
            StoreService.RestoreResult.restored,
            .nothingToRestore,
            .entitlementMismatch,
            .failed,
            .notConfigured,
        ].map(\.rawValue)
        #expect(Set(raw).count == raw.count)
        #expect(raw.allSatisfy { AnalyticsService.allowsProperty(key: "result", value: $0) })
    }

    /// `languagesNotDownloaded` used to absorb every failure — a declined download, a network
    /// fault and a mid-run shape error alike — which is why 5 of 6 production runs reported it.
    @Test func translationResultsSeparateTheFailureModes() {
        let raw: [String] = [
            TranslationRunResult.completed,
            .languagesNotDownloaded,
            .downloadFailed,
            .unsupportedPair,
            .translationFailed,
        ].map(\.rawValue)
        #expect(Set(raw).count == raw.count)
        #expect(raw.allSatisfy { AnalyticsService.allowsProperty(key: "result", value: $0) })

        #expect(TranslationRunResult.completed.isRetryable == false)
        #expect(TranslationRunResult.unsupportedPair.isRetryable == false)
        #expect(TranslationRunResult.languagesNotDownloaded.isRetryable)
        #expect(TranslationRunResult.downloadFailed.isRetryable)
        #expect(TranslationRunResult.translationFailed.isRetryable)
    }

    /// Every non-success result must reach the user as an alert; a silent failure is how the
    /// translation wall went unreported for three releases.
    @Test func everyTranslationFailureProducesAnIssue() {
        #expect(TranslationLanguageIssue(.completed, language: "German") == nil)
        for result in [TranslationRunResult.languagesNotDownloaded, .downloadFailed, .unsupportedPair, .translationFailed] {
            #expect(TranslationLanguageIssue(result, language: "German") != nil, "\(result.rawValue) has no alert")
        }
        #expect(TranslationLanguageIssue(.unsupportedPair, language: "German")?.offersRetry == false)
        #expect(TranslationLanguageIssue(.languagesNotDownloaded, language: "German")?.offersRetry == true)
    }
}
