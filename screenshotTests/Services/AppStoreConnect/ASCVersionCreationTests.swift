import CoreGraphics
import Foundation
@testable import Screenshot_Bro
import Testing

// When every version on an app is live or in review, the version step is a dead end unless the
// wizard can create the next one. What matters is what it offers and what it prefills — a wrong
// version number is a record the user then has to clean up in App Store Connect.
@MainActor
struct ASCVersionCreationTests {

    private final class Harness {
        let model: ASCUploadFlowModel
        let api: FakeASCUploadAPI
        let document: StubASCDocument

        init(mode: ASCFlowMode = .screenshots, versions: [(String, String, ASCPlatform)]) {
            api = FakeASCUploadAPI()
            document = StubASCDocument()
            model = ASCUploadFlowModel(
                mode: mode,
                api: api,
                credentials: AppStoreConnectCredentialsStore.isolatedForTesting()
            )
            model.bind(document: document)
            model.selectedApp = ASCApp(
                id: "app-1",
                attributes: .init(name: "Fixture", bundleId: "com.example.fixture", sku: nil, primaryLocale: nil)
            )
            model.versions = versions.map { versionString, state, platform in
                ASCAppStoreVersion(
                    id: "\(platform.rawValue)-\(versionString)",
                    attributes: .init(versionString: versionString, appStoreState: state, platform: platform.rawValue)
                )
            }
        }
    }

    // MARK: - What is offered

    @Test func nothingIsOfferedWhileAnEditableVersionExists() {
        let h = Harness(versions: [
            ("4.14", "READY_FOR_SALE", .ios),
            ("4.15", "PREPARE_FOR_SUBMISSION", .ios)
        ])
        #expect(h.model.platformsAwaitingAVersion.isEmpty)
    }

    @Test func everyShippedPlatformIsOfferedOnceWhenAllVersionsAreLocked() {
        let h = Harness(versions: [
            ("4.13", "READY_FOR_SALE", .ios),
            ("4.14", "WAITING_FOR_REVIEW", .ios),
            ("4.14", "READY_FOR_SALE", .macOS)
        ])
        #expect(h.model.platformsAwaitingAVersion == [.ios, .macOS])
    }

    /// `WAITING_FOR_REVIEW` is editable for metadata but not for screenshots, so the two modes
    /// disagree about whether there is anything to create.
    @Test func theModeDecidesWhetherALockedVersionCounts() {
        let versions = [("4.14", "WAITING_FOR_REVIEW", ASCPlatform.ios)]
        #expect(Harness(mode: .screenshots, versions: versions).model.platformsAwaitingAVersion == [.ios])
        #expect(Harness(mode: .metadata, versions: versions).model.platformsAwaitingAVersion.isEmpty)
    }

    // MARK: - The suggested number

    @Test func theSuggestionBumpsTheHighestVersionOfThatPlatform() {
        let h = Harness(versions: [
            ("4.9", "READY_FOR_SALE", .ios),
            ("4.14", "READY_FOR_SALE", .ios),
            ("2.1.3", "READY_FOR_SALE", .macOS)
        ])
        #expect(h.model.suggestedVersionString(platform: .ios) == "4.15", "4.14 outranks 4.9")
        #expect(h.model.suggestedVersionString(platform: .macOS) == "2.1.4")
        #expect(h.model.suggestedVersionString(platform: .tvOS) == nil)
    }

    // MARK: - Creating

    @Test func aCreatedVersionJoinsTheListAndBecomesTheSelection() async {
        let h = Harness(versions: [("4.14", "READY_FOR_SALE", .ios)])

        await h.model.createAppStoreVersion(platform: .ios, versionString: "4.15")

        #expect(h.api.createVersionCalls.count == 1)
        #expect(h.api.createVersionCalls.first?.appId == "app-1")
        #expect(h.api.createVersionCalls.first?.versionString == "4.15")
        #expect(h.model.versions.count == 2)
        #expect(h.model.versions.first?.attributes.versionString == "4.15", "selectable versions sort first")
        #expect(h.model.selectedVersionIds == [h.model.versions[0].id])
        #expect(h.model.versionCreationError == nil)
        #expect(h.model.creatingVersionPlatform == nil)
    }

    @Test func whitespaceAroundTheTypedNumberIsTrimmed() async {
        let h = Harness(versions: [("4.14", "READY_FOR_SALE", .ios)])

        await h.model.createAppStoreVersion(platform: .ios, versionString: "  4.15 ")

        #expect(h.api.createVersionCalls.first?.versionString == "4.15")
    }

    @Test func anEmptyNumberIsNeverPosted() async {
        let h = Harness(versions: [("4.14", "READY_FOR_SALE", .ios)])

        await h.model.createAppStoreVersion(platform: .ios, versionString: "   ")

        #expect(h.api.createVersionCalls.isEmpty)
    }

    /// App Store Connect rejects a version string that isn't greater than the current release.
    @Test func aRejectionShowsOnTheStepAndLeavesTheListAlone() async {
        let h = Harness(versions: [("4.14", "READY_FOR_SALE", .ios)])
        h.api.createVersionResults = [
            .failure(AppStoreConnectAPIError.httpError(status: 409, message: "The version number must be greater"))
        ]

        await h.model.createAppStoreVersion(platform: .ios, versionString: "4.14")

        #expect(h.model.versionCreationError != nil)
        #expect(h.model.versions.count == 1)
        #expect(h.model.creatingVersionPlatform == nil)
        #expect(h.model.errorMessage == nil, "the step's own banner stays clear")
    }
}
