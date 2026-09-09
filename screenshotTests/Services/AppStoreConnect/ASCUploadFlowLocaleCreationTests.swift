import CoreGraphics
import Foundation
@testable import Screenshot_Bro
import Testing

// The plan step can create the App Store localization a project locale has no match for. The
// value of the feature is entirely in what happens *after* the POST — the row has to flip from
// "No matching App Store locale" to matched, selected and enabled — so that is what these cover.
@MainActor
struct ASCUploadFlowLocaleCreationTests {

    /// The model holds its document weakly, so the test has to keep it alive.
    private final class Harness {
        let model: ASCUploadFlowModel
        let api: FakeASCUploadAPI
        let document: StubASCDocument

        init(projectLocales: [String], versionState: String = "PREPARE_FOR_SUBMISSION") {
            var localeState = LocaleState.default
            // `baseLocaleCode` is the first locale, which is what the copy fallback reads.
            localeState.locales = projectLocales.map { LocaleDefinition(code: $0, label: $0.uppercased()) }

            api = FakeASCUploadAPI()
            document = StubASCDocument(
                rows: [
                    ScreenshotRow(
                        label: "Row",
                        templates: [ScreenshotTemplate(), ScreenshotTemplate()],
                        templateWidth: 1290,
                        templateHeight: 2796
                    )
                ],
                localeState: localeState
            )
            model = ASCUploadFlowModel(
                api: api,
                credentials: AppStoreConnectCredentialsStore.isolatedForTesting()
            )
            model.bind(document: document)
            model.versions = ["ios-version", "mac-version"].map {
                ASCAppStoreVersion(
                    id: $0,
                    attributes: .init(versionString: "1.0", appStoreState: versionState, platform: "IOS")
                )
            }
            model.selectedVersionIds = ["ios-version", "mac-version"]
        }

        /// Seed each selected version with one existing localization and build the plans, exactly
        /// as `moveToPlan` would after a fetch.
        func buildPlans(existing: [String]) {
            for version in model.selectedVersions {
                model.localizationsByVersionId[version.id] = existing.map { locale in
                    ASCAppStoreVersionLocalization(
                        id: "\(version.id)-\(locale)",
                        attributes: .init(locale: locale, description: "Base copy", keywords: "a, b")
                    )
                }
            }
            model.updateDestinationPlans(model.buildDestinationPlans())
        }

        func target(versionId: String, localeCode: String) -> ASCLocaleTarget? {
            model.destinationPlans
                .first { $0.id == versionId }?
                .rowPlans.first?
                .localeTargets.first { $0.appLocaleCode == localeCode }
        }
    }

    // MARK: - Success

    @Test func creatingALocaleMakesTheRowMatchedSelectedAndEnabled() async {
        let h = Harness(projectLocales: ["en", "de"])
        h.buildPlans(existing: ["en-US"])
        #expect(h.target(versionId: "ios-version", localeCode: "de")?.candidates.isEmpty == true)

        await h.model.createAppStoreLocalization(projectLocaleCode: "de", versionId: "ios-version")

        let created = h.target(versionId: "ios-version", localeCode: "de")
        #expect(created?.candidates.count == 1)
        #expect(created?.candidates.first?.attributes.locale == "de-DE")
        #expect(created?.isEnabled == true, "a target force-disabled while unmatched must come back on")
        #expect(created?.selectedASCLocalizationIds.count == 1)
        #expect(h.model.localeCreationErrors.isEmpty)
        #expect(h.model.creatingLocaleKeys.isEmpty)
    }

    /// The project code is not what goes on the wire — the App Store language code is.
    @Test func thePostCarriesTheMappedAppStoreLanguageCode() async {
        let h = Harness(projectLocales: ["en", "zh"])
        h.buildPlans(existing: ["en-US"])

        await h.model.createAppStoreLocalization(projectLocaleCode: "zh", versionId: "ios-version")

        #expect(h.api.createCalls.count == 1)
        #expect(h.api.createCalls.first?.locale == "zh-Hans")
        #expect(h.api.createCalls.first?.versionId == "ios-version")
    }

    @Test func creatingOnOneVersionLeavesTheOtherUnmatched() async {
        let h = Harness(projectLocales: ["en", "de"])
        h.buildPlans(existing: ["en-US"])

        await h.model.createAppStoreLocalization(projectLocaleCode: "de", versionId: "ios-version")

        #expect(h.target(versionId: "ios-version", localeCode: "de")?.candidates.count == 1)
        #expect(h.target(versionId: "mac-version", localeCode: "de")?.candidates.isEmpty == true)
    }

    /// A locale the user deliberately unticked must stay unticked across the rebuild.
    @Test func creatingALocaleDoesNotReviveALocaleTheUserUnticked() async {
        let h = Harness(projectLocales: ["en", "de"])
        h.buildPlans(existing: ["en-US"])
        var plans = h.model.destinationPlans
        for i in plans.indices {
            for j in plans[i].rowPlans.indices {
                for k in plans[i].rowPlans[j].localeTargets.indices
                where plans[i].rowPlans[j].localeTargets[k].appLocaleCode == "en" {
                    plans[i].rowPlans[j].localeTargets[k].isEnabled = false
                }
            }
        }
        h.model.updateDestinationPlans(plans)

        await h.model.createAppStoreLocalization(projectLocaleCode: "de", versionId: "ios-version")

        #expect(h.target(versionId: "ios-version", localeCode: "en")?.isEnabled == false)
    }

    /// A Refresh can land mid-create, so the merge must not leave two candidates sharing an id.
    @Test func aRefetchLandingMidCreateDoesNotDuplicateTheCandidate() async {
        let h = Harness(projectLocales: ["en", "de"])
        h.buildPlans(existing: ["en-US"])
        h.api.createResults = [
            .success(ASCAppStoreVersionLocalization(id: "ios-version-de-DE", attributes: .init(locale: "de-DE")))
        ]
        // What a refresh completing first would have left behind.
        h.model.localizationsByVersionId["ios-version"]?.append(
            ASCAppStoreVersionLocalization(id: "ios-version-de-DE", attributes: .init(locale: "de-DE"))
        )

        await h.model.createAppStoreLocalization(projectLocaleCode: "de", versionId: "ios-version")

        let ids = h.model.localizationsByVersionId["ios-version"]?.map(\.id) ?? []
        #expect(Set(ids).count == ids.count, "no duplicate ids: \(ids)")
    }

    // MARK: - Nothing worth offering

    @Test func aLocaleTheAppStoreDoesNotOfferIsNeverPosted() async {
        let h = Harness(projectLocales: ["en", "sw"])
        h.buildPlans(existing: ["en-US"])

        await h.model.createAppStoreLocalization(projectLocaleCode: "sw", versionId: "ios-version")

        #expect(h.api.createCalls.isEmpty)
        #expect(h.model.localeCreationErrors.isEmpty)
    }

    /// A project carrying both `en` and `en-US` leaves `en` unmatched, because `ASCLocaleMatcher`
    /// gives the `en-US` localization to the longer code. Creating `en-US` again is a duplicate.
    @Test func aStoreCodeAnotherProjectLocaleAlreadyClaimedIsNeverPosted() async {
        let h = Harness(projectLocales: ["en", "en-US"])
        h.buildPlans(existing: ["en-US"])
        #expect(h.target(versionId: "ios-version", localeCode: "en")?.candidates.isEmpty == true)

        await h.model.createAppStoreLocalization(projectLocaleCode: "en", versionId: "ios-version")

        #expect(h.api.createCalls.isEmpty)
        #expect(h.model.existingStoreLocaleCodes(versionId: "ios-version") == ["en-us"])
    }

    // MARK: - Failure

    @Test func aRejectedLocaleReportsOnItsOwnRowAndNotTheWholeStep() async {
        let h = Harness(projectLocales: ["en", "de"])
        h.buildPlans(existing: ["en-US"])
        h.api.createResults = [.failure(AppStoreConnectAPIError.httpError(status: 409, message: "STATE_ERROR"))]

        await h.model.createAppStoreLocalization(projectLocaleCode: "de", versionId: "ios-version")

        let key = ASCUploadFlowModel.localeCreationKey(versionId: "ios-version", projectLocaleCode: "de")
        #expect(h.model.localeCreationErrors[key] != nil)
        #expect(h.model.errorMessage == nil, "one locale must not blank out the plan screen")
        #expect(h.target(versionId: "ios-version", localeCode: "de")?.candidates.isEmpty == true)
        #expect(h.model.creatingLocaleKeys.isEmpty)
    }

    /// App Store Connect refuses a locale-only create for a listing that requires copy per
    /// language; the retry copies the base locale's so the user isn't sent to the website.
    @Test func aCreateRejectedForMissingCopyRetriesWithTheBaseLocalesCopy() async {
        let h = Harness(projectLocales: ["en", "de"])
        h.buildPlans(existing: ["en-US"])
        h.api.createResults = [
            .failure(AppStoreConnectAPIError.httpError(
                status: 400,
                message: "ENTITY_ERROR.ATTRIBUTE.REQUIRED: description"
            )),
            .success(ASCAppStoreVersionLocalization(id: "new-de", attributes: .init(locale: "de-DE")))
        ]

        await h.model.createAppStoreLocalization(projectLocaleCode: "de", versionId: "ios-version")

        #expect(h.api.createCalls.count == 2)
        #expect(h.api.createCalls.first?.attributeKeys.isEmpty == true)
        #expect(h.api.createCalls.last?.attributeKeys == ["description"], "only what the rejection named")
        #expect(h.target(versionId: "ios-version", localeCode: "de")?.candidates.count == 1)
        #expect(h.model.localeCreationErrors.isEmpty)
    }

    /// A shipped app's version is rejected for release notes as well as a description. Answering
    /// only half the complaint would fail again, so the retry carries every attribute named.
    @Test func aRejectionNamingSeveralAttributesRetriesWithAllOfThem() async {
        let h = Harness(projectLocales: ["en", "de"])
        h.buildPlans(existing: ["en-US"])
        h.api.createResults = [
            .failure(AppStoreConnectAPIError.httpError(
                status: 400,
                message: "ENTITY_ERROR.ATTRIBUTE.REQUIRED: description\nENTITY_ERROR.ATTRIBUTE.REQUIRED: whatsNew"
            )),
            .success(ASCAppStoreVersionLocalization(id: "new-de", attributes: .init(locale: "de-DE")))
        ]

        await h.model.createAppStoreLocalization(projectLocaleCode: "de", versionId: "ios-version")

        #expect(h.api.createCalls.count == 2)
        #expect(h.api.createCalls.last?.attributeKeys == ["description", "whatsNew"])
    }

    @Test func anUnrelatedRejectionIsNotRetried() async {
        let h = Harness(projectLocales: ["en", "de"])
        h.buildPlans(existing: ["en-US"])
        h.api.createResults = [
            .failure(AppStoreConnectAPIError.httpError(status: 409, message: "STATE_ERROR")),
            .success(ASCAppStoreVersionLocalization(id: "new-de", attributes: .init(locale: "de-DE")))
        ]

        await h.model.createAppStoreLocalization(projectLocaleCode: "de", versionId: "ios-version")

        #expect(h.api.createCalls.count == 1)
    }

    /// With no base-locale description to copy there is nothing to retry with, so the original
    /// rejection is what the row shows.
    @Test func withoutBaseCopyTheRequiredAttributeRejectionSurfaces() async {
        let h = Harness(projectLocales: ["en", "de"])
        h.buildPlans(existing: [])
        h.api.createResults = [
            .failure(AppStoreConnectAPIError.httpError(
                status: 400,
                message: "ENTITY_ERROR.ATTRIBUTE.REQUIRED: description"
            ))
        ]

        await h.model.createAppStoreLocalization(projectLocaleCode: "de", versionId: "ios-version")

        #expect(h.api.createCalls.count == 1)
        let key = ASCUploadFlowModel.localeCreationKey(versionId: "ios-version", projectLocaleCode: "de")
        #expect(h.model.localeCreationErrors[key] != nil)
    }
}
