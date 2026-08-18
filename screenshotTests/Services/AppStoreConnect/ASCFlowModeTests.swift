import Foundation
@testable import Screenshot_Bro
import Testing

struct ASCFlowModeTests {
    private func version(_ state: String) -> ASCAppStoreVersion {
        ASCAppStoreVersion(
            id: "version-\(state)",
            attributes: .init(versionString: "1.0", appStoreState: state, platform: "IOS")
        )
    }

    private let app = ASCApp(
        id: "app-1",
        attributes: .init(name: "App", bundleId: "com.example.app", sku: nil, primaryLocale: "en-US")
    )

    @Test func metadataModeAcceptsReviewLockedVersions() {
        let inReview = version("IN_REVIEW")
        let waitingForReview = version("WAITING_FOR_REVIEW")

        #expect(inReview.isSelectable(for: .metadata))
        #expect(waitingForReview.isSelectable(for: .metadata))
        #expect(!inReview.isSelectable(for: .screenshots))
        #expect(!waitingForReview.isSelectable(for: .screenshots))
    }

    @Test func bothModesAcceptPrepareForSubmissionAndRejectLiveVersions() {
        let editable = version("PREPARE_FOR_SUBMISSION")
        let live = version("READY_FOR_SALE")

        #expect(editable.isSelectable(for: .metadata))
        #expect(editable.isSelectable(for: .screenshots))
        #expect(!live.isSelectable(for: .metadata))
        #expect(!live.isSelectable(for: .screenshots))
    }

    @Test func appSelectabilityFollowsTheMode() {
        let reviewOnly = ASCAppWithVersions(app: app, versions: [version("IN_REVIEW")])
        let live = ASCAppWithVersions(app: app, versions: [version("READY_FOR_SALE")])
        let editable = ASCAppWithVersions(app: app, versions: [version("READY_FOR_SALE"), version("REJECTED")])

        #expect(reviewOnly.hasSelectableVersion(for: .metadata))
        #expect(!reviewOnly.hasSelectableVersion(for: .screenshots))
        #expect(!live.hasSelectableVersion(for: .metadata))
        #expect(!live.hasSelectableVersion(for: .screenshots))
        #expect(editable.hasSelectableVersion(for: .metadata))
        #expect(editable.hasSelectableVersion(for: .screenshots))
    }

    /// Metadata edits don't involve rows, so the default selection is every editable version —
    /// no display-type compatibility pass (which would need the project's rows).
    @Test func metadataModePreselectsEveryEditableVersion() {
        let flow = UploadToAppStoreConnectView(mode: .metadata)
        let versions = [
            version("PREPARE_FOR_SUBMISSION"),
            version("IN_REVIEW"),
            version("READY_FOR_SALE")
        ]

        let selected = flow.defaultSelectedVersionIds(from: versions)

        #expect(selected == ["version-PREPARE_FOR_SUBMISSION", "version-IN_REVIEW"])
    }
}
