import Foundation
@testable import Screenshot_Bro
import Testing

// The App Store Connect and Google Play wizards each had their own copy of this composition.
// These pin the behaviour both copies had, so the shared version can't quietly drop a section.
struct StoreUploadFailureTextTests {

    private struct PlainError: Error, LocalizedError {
        var errorDescription: String? { "something went wrong" }
    }

    private struct DescribedError: StoreUploadErrorDescribing, LocalizedError {
        var errorDescription: String? { "the localized description" }
        var summaryDescription: String { "a short summary" }
        var technicalDescription: String { "HTTP 409\nbody" }
    }

    @Test func summaryPrefersTheErrorsOwnSummary() {
        #expect(StoreUploadFailureText.summary(for: DescribedError()) == "a short summary")
    }

    /// An error that isn't one of ours (a URLError, a decoding failure) still has to produce a
    /// sentence, not an empty banner.
    @Test func summaryFallsBackToTheLocalizedDescription() {
        let summary = StoreUploadFailureText.summary(for: PlainError())
        #expect(summary.contains("something went wrong"))
    }

    @Test func detailsPutTheErrorFirstThenContextThenTechnicalText() {
        let details = StoreUploadFailureText.details(
            for: DescribedError(),
            context: ["App: Demo (com.example.demo)", "Versions:\n1.0 · Prepare for Submission"]
        )
        let sections = details.components(separatedBy: "\n\n")
        #expect(sections.count == 4)
        #expect(sections[0] == "the localized description")
        #expect(sections[1] == "App: Demo (com.example.demo)")
        #expect(sections[2] == "Versions:\n1.0 · Prepare for Submission")
        #expect(sections[3] == "Technical details:\nHTTP 409\nbody")
    }

    @Test func detailsOmitTheTechnicalSectionForAnUndescribedError() {
        let details = StoreUploadFailureText.details(for: PlainError(), context: ["Package: com.example"])
        #expect(details.contains("Technical details") == false)
        #expect(details.contains("Package: com.example"))
    }

    @Test func detailsWorkWithNoContextAtAll() {
        let details = StoreUploadFailureText.details(for: PlainError())
        #expect(details == "something went wrong")
    }

    /// Both shipping error types must actually adopt the protocol, or the wizards silently fall
    /// back to the generic summary and lose their technical section.
    @Test func bothStoreUploadErrorsAreDescribing() {
        let asc: Error = AppStoreConnectUploadError.noRowsSelected
        let play: Error = GooglePlayUploadError.noRowsSelected
        #expect(asc is any StoreUploadErrorDescribing)
        #expect(play is any StoreUploadErrorDescribing)
        #expect(StoreUploadFailureText.summary(for: asc) == AppStoreConnectUploadError.noRowsSelected.summaryDescription)
        #expect(StoreUploadFailureText.summary(for: play) == GooglePlayUploadError.noRowsSelected.summaryDescription)
    }
}
