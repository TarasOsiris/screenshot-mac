import CoreGraphics
import Foundation
@testable import Screenshot_Bro
import Testing

/// What the user is told when an upload fails, and whether the step is worth repeating.
struct GPUploadFailureContextTests {
    private func context(_ error: Error, operation: String = "upload screenshot 8") -> GPUploadFailureContext {
        GPUploadFailureContext(
            operation: operation,
            target: GPUploadTarget(
                rowId: UUID(),
                rowLabel: "Android Phone",
                rowSize: CGSize(width: 1080, height: 2160),
                imageType: .phoneScreenshots,
                languages: [],
                templateCount: 8
            ),
            language: GPUploadLanguage(projectCode: "pt-BR", playCode: "pt-BR", label: "Portuguese (Brazil)"),
            underlyingError: error
        )
    }

    private func transport(_ code: URLError.Code) -> GPUploadFailureContext {
        context(GooglePlayAPIError.transport(URLError(code)))
    }

    /// The reported failure: a timed-out request was described as Google Play refusing it, which
    /// sent the user checking a package name, image type and language that were all correct.
    @Test func aTimeoutIsNotReportedAsARejection() {
        let message = transport(.timedOut).detailedMessage
        #expect(!message.contains("did not accept the request"))
        #expect(message.contains("Google Play never saw it"))
        #expect(message.contains("listing is unchanged"), "the edit is abandoned, so say so")
    }

    @Test func beingOfflineSaysSoRatherThanBlamingTheRequest() {
        let context = transport(.notConnectedToInternet)
        #expect(context.summaryMessage.contains("No internet connection"))
        #expect(context.detailedMessage.contains("lost its internet connection"))
    }

    @Test func aRealRejectionStillReadsAsOne() {
        let message = context(GooglePlayAPIError.httpError(status: 400, message: "Bad image")).detailedMessage
        #expect(message.contains("did not accept the request"))
    }

    @Test func anAuthFailureKeepsItsOwnAdvice() {
        let message = context(GooglePlayAPIError.httpError(status: 403, message: "forbidden")).detailedMessage
        #expect(message.contains("Users and permissions"))
    }

    // MARK: - Worth retrying

    private let policy = StoreRetryPolicy()

    /// The reported failure. `.timedOut` is ambiguous — the upload may have landed — so it is only
    /// repeatable because the publish sequence clears the set before it re-uploads.
    @Test func connectionFailuresAreWorthRetrying() {
        #expect(transport(.timedOut).isWorthRetrying(under: policy))
        #expect(transport(.networkConnectionLost).isWorthRetrying(under: policy))
        #expect(transport(.notConnectedToInternet).isWorthRetrying(under: policy))
    }

    /// One representative each; which statuses are transient is `StoreRetryPolicy`'s to say.
    @Test func serverHiccupsRetryAndRejectionsDoNot() {
        #expect(context(GooglePlayAPIError.httpError(status: 503, message: "busy")).isWorthRetrying(under: policy))
        #expect(!context(GooglePlayAPIError.httpError(status: 400, message: "bad")).isWorthRetrying(under: policy))
    }

    @Test func aFailureWithNoNetworkCauseIsNotRetried() {
        let decodingFailure = context(GooglePlayAPIError.decodingFailed(URLError(.badServerResponse)))
        #expect(!decodingFailure.isWorthRetrying(under: policy))
        #expect(!decodingFailure.isConnectionFailure, "a bad response body is not a connection problem")
    }
}
