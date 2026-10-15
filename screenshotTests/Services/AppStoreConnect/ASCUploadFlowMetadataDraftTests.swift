import Foundation
@testable import Screenshot_Bro
import Testing

// The metadata step must only write what the user typed. Release notes in particular: filling an
// empty "What's New" with another locale's notes or a placeholder would be PATCHed on save and
// silence App Store Connect's missing-release-notes check at submission.
@MainActor
struct ASCUploadFlowMetadataDraftTests {

    @Test func emptyReleaseNotesStayEmptyAndNothingIsSaved() {
        let api = FakeASCUploadAPI()
        let model = ASCUploadFlowModel(api: api, credentials: AppStoreConnectCredentialsStore.isolatedForTesting())
        model.versions = [
            ASCAppStoreVersion(
                id: "ios-version",
                attributes: .init(versionString: "1.1", appStoreState: "PREPARE_FOR_SUBMISSION", platform: "IOS")
            )
        ]
        model.selectedVersionIds = ["ios-version"]
        model.localizationsByVersionId["ios-version"] = [
            ASCAppStoreVersionLocalization(
                id: "en",
                attributes: .init(locale: "en-US", description: "Copy", whatsNew: "Faster exports")
            ),
            ASCAppStoreVersionLocalization(id: "de", attributes: .init(locale: "de-DE", description: "Text"))
        ]

        model.buildMetadataDrafts(appInfoLocalizations: [])

        let drafts = Dictionary(uniqueKeysWithValues: model.versionDrafts.map { ($0.locale, $0) })
        #expect(drafts["en-US"]?.whatsNew == "Faster exports")
        #expect(drafts["de-DE"]?.whatsNew == "")
        #expect(model.versionDrafts.allSatisfy { !$0.isChanged }, "an untouched draft must not be PATCHed")
    }
}
