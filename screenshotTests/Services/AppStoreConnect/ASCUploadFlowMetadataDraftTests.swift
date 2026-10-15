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

    private func modelWithTwoLocales() -> ASCUploadFlowModel {
        let model = ASCUploadFlowModel(api: FakeASCUploadAPI(), credentials: AppStoreConnectCredentialsStore.isolatedForTesting())
        model.versions = [
            ASCAppStoreVersion(id: "v", attributes: .init(versionString: "1.1", appStoreState: "PREPARE_FOR_SUBMISSION", platform: "IOS"))
        ]
        model.selectedVersionIds = ["v"]
        model.metadataVersionId = "v"
        model.localizationsByVersionId["v"] = [
            ASCAppStoreVersionLocalization(id: "en", attributes: .init(locale: "en-US")),
            ASCAppStoreVersionLocalization(id: "de", attributes: .init(locale: "de-DE")),
        ]
        model.buildMetadataDrafts(appInfoLocalizations: [])
        return model
    }

    @Test func anOverLongFieldBlocksTheSaveUntilItFits() throws {
        let model = modelWithTwoLocales()
        let index = try #require(model.versionDrafts.firstIndex { $0.locale == "de-DE" })
        #expect(model.metadataWithinLimits)

        model.versionDrafts[index].keywords = String(repeating: "k", count: 101)
        #expect(!model.metadataWithinLimits)
        #expect(model.hasMetadataChanges)
        #expect(model.metadataLocalesWithChanges == ["de-DE"])

        model.versionDrafts[index].keywords = String(repeating: "k", count: 100)
        #expect(model.metadataWithinLimits)
    }

    @Test func englishReleaseNotesCopyToTheVersionsOtherLocales() throws {
        let model = modelWithTwoLocales()
        let english = try #require(model.versionDrafts.firstIndex { $0.locale == "en-US" })
        #expect(!model.canCopyWhatsNewToOtherLocales(from: english), "nothing to copy yet")

        model.versionDrafts[english].whatsNew = "Bug fixes"
        #expect(model.canCopyWhatsNewToOtherLocales(from: english))
        model.copyWhatsNewToOtherLocales(from: english)

        #expect(model.versionDrafts.allSatisfy { $0.whatsNew == "Bug fixes" })
    }

    @Test func copyrightChangesAreTrackedPerVersion() {
        let model = modelWithTwoLocales()
        #expect(!model.activeVersionCopyrightChanged)
        model.copyrightByVersion["v"] = "© 2026 Example"
        #expect(model.activeVersionCopyrightChanged)
        #expect(model.changedCopyrights == ["v": "© 2026 Example"])
    }

    /// The MCP tool's argument keys are the snake-cased attributes it documents.
    @Test func metadataArgumentKeysAreSnakeCase() {
        #expect(ASCMetadataField.privacyPolicyUrl.argumentKey == "privacy_policy_url")
        #expect(ASCMetadataField.whatsNew.argumentKey == "whats_new")
        #expect(ASCMetadataField.description.argumentKey == "description")
    }
}
