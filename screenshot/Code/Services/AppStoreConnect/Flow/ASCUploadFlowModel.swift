import Foundation
import Observation

/// The App Store Connect upload/metadata wizard's state machine.
///
/// All of this used to be 29 `@State` properties on `UploadToAppStoreConnectView` plus a
/// 580-line extension containing no view code, which meant none of it — plan construction,
/// step transitions, draft diffing, cancellation, error composition — could be tested. Follows
/// `ExportFlowModel`: a `@MainActor @Observable` class behind a narrow document protocol, with
/// its collaborators injected.
@MainActor
@Observable
final class ASCUploadFlowModel {

    // MARK: - Flow state

    private(set) var step: ASCUploadStep = .pickingApp

    var appsWithVersions: [ASCAppWithVersions] = []
    var selectedApp: ASCApp?

    var versions: [ASCAppStoreVersion] = []
    var selectedVersionIds: Set<String> = []
    var localizationsByVersionId: [String: [ASCAppStoreVersionLocalization]] = [:]

    var versionDrafts: [ASCVersionLocaleDraft] = []
    var appInfoDrafts: [ASCAppInfoLocaleDraft] = []
    var copyrightByVersion: [String: String] = [:]
    var originalCopyrightByVersion: [String: String] = [:]
    /// Not merely UI selection: `buildMetadataDrafts` picks it and `moveToMetadata` re-validates it.
    var selectedMetadataLocale: String?
    /// The version whose metadata the editing screen is currently showing (the active tab).
    var metadataVersionId: String?

    /// `private(set)` with a single writer so `planEntries` cannot go stale: every write, including
    /// the view's `ForEach` binding, goes through `updateDestinationPlans`.
    private(set) var destinationPlans: [ASCDestinationPlan] = []
    private(set) var planEntries: ASCUploadPlanEntries = .empty

    var uploadProgress: UploadProgress?
    var uploadSummary: ASCUploadSummary?
    var metadataSummary: ASCMetadataSaveSummary?

    var errorMessage: String?
    /// Full error text (summary + API response + context). When nil, the Details button falls
    /// back to `errorMessage`.
    var errorDetailsText: String?
    var isBusy = false

    // MARK: - Collaborators

    let mode: ASCFlowMode
    let credentials: AppStoreConnectCredentialsStore
    /// Owns the temp folder holding rendered screenshots; released by `discardPlan`, which is why
    /// `tearDown()` must run when the wizard disappears.
    let screenshotSync: ASCScreenshotSyncCoordinator

    @ObservationIgnored let api: any ASCUploadAPI
    @ObservationIgnored private(set) weak var document: (any ASCUploadDocument)?
    @ObservationIgnored var uploadTask: Task<Void, Never>?

    /// Called after `step` advances. iPad pushes onto its `NavigationStack` path here; macOS does
    /// nothing. Injected for the same reason `ExportFlowModel.requestReview` is: the model cannot
    /// perform it, and a test must be able to observe it without a view.
    @ObservationIgnored var navigationDidAdvance: (ASCUploadStep) -> Void = { _ in }
    /// Called after a retreat, so iPad can pop the terminal screen it pushed.
    @ObservationIgnored var navigationWillRetreat: () -> Void = {}

    init(
        mode: ASCFlowMode = .screenshots,
        api: any ASCUploadAPI = AppStoreConnectAPIService.shared,
        credentials: AppStoreConnectCredentialsStore = .shared,
        screenshotSync: ASCScreenshotSyncCoordinator = ASCScreenshotSyncCoordinator()
    ) {
        self.mode = mode
        self.api = api
        self.credentials = credentials
        self.screenshotSync = screenshotSync
    }

    /// Called from the view's `.task`. `weak` because the document outlives the wizard.
    func bind(document: any ASCUploadDocument) {
        self.document = document
    }

    // MARK: - Derived

    /// The document's rows, or none while unbound. Reading through the document rather than
    /// copying it keeps the plan in step with edits made while the wizard is open.
    var rows: [ScreenshotRow] { document?.rows ?? [] }

    var localeState: LocaleState { document?.localeState ?? .default }

    var apps: [ASCApp] { appsWithVersions.map(\.app) }

    var selectedVersions: [ASCAppStoreVersion] {
        versions.filter { selectedVersionIds.contains($0.id) }
    }

    var selectedVersion: ASCAppStoreVersion? {
        let selected = selectedVersions
        return selected.count == 1 ? selected.first : nil
    }

    /// The selected version whose metadata the editing screen is showing (the active tab).
    var activeMetadataVersion: ASCAppStoreVersion? {
        selectedVersions.first { $0.id == metadataVersionId } ?? selectedVersions.first
    }

    // MARK: - Plan

    func updateDestinationPlans(_ plans: [ASCDestinationPlan]) {
        destinationPlans = plans
        planEntries = ASCUploadPlanEntries(destinations: plans)
    }

    // MARK: - Navigation

    /// Move forward one step. macOS swaps the single-screen state; iPad pushes onto the stack.
    func advance(to next: ASCUploadStep) {
        step = next
        navigationDidAdvance(next)
    }

    /// Swap the terminal screen's content without a push. iPad already pushed `.uploading`, and
    /// the done screen flips that same screen on `step` — pushing again would stack a duplicate.
    func completeTerminalStep(_ next: ASCUploadStep) {
        step = next
    }

    /// Return to the originating plan/review after a sync error or cancellation.
    func retreatAfterScreenshotSync(to destination: ASCUploadStep) {
        step = destination
        navigationWillRetreat()
    }

    /// Step back one screen, clearing whatever failed on the screen being left. Leaving the
    /// review screen also discards the sync plan, releasing its temp folder.
    func goBack() {
        errorMessage = nil
        errorDetailsText = nil
        switch step {
        case .pickingVersion: step = .pickingApp
        case .editingMetadata: step = .pickingVersion
        case .configuringPlan: step = .editingMetadata
        case .reviewingChanges:
            screenshotSync.discard()
            step = .configuringPlan
        default: break
        }
    }

    /// iPad's system Back button pops the `NavigationStack` without going through `advance(to:)`,
    /// so the model has to be told. Compiled on every platform — this used to live behind
    /// `#if os(iOS)`, where the macOS test run could never reach it.
    func handlePathChange(from oldPath: [ASCUploadStep], to newPath: [ASCUploadStep]) {
        step = newPath.last ?? .pickingApp
        // A user-initiated Back clears a stale error banner (matching `goBack()`). An upload
        // error/cancel retreat pops the .uploading/.done screen *after* setting errorMessage, so
        // keep that one — the plan screen explains why it stopped.
        guard newPath.count < oldPath.count,
              oldPath.last != .uploading, oldPath.last != .done
        else { return }
        if oldPath.last == .reviewingChanges, screenshotSync.phase == .loading {
            uploadTask?.cancel()
        }
        errorMessage = nil
        errorDetailsText = nil
        if oldPath.last == .reviewingChanges {
            screenshotSync.discard()
        }
    }

    /// Cancels an in-flight upload and releases the sync plan's temp folder. The view calls this
    /// from `.onDisappear`; without the discard the rendered screenshots leak.
    func tearDown() {
        uploadTask?.cancel()
        uploadTask = nil
        screenshotSync.discard()
        // Belt and braces against the capture hazard documented where these are assigned.
        navigationDidAdvance = { _ in }
        navigationWillRetreat = {}
    }
}
