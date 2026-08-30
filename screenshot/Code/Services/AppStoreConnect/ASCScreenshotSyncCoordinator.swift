import Foundation
import Observation

@MainActor
@Observable
final class ASCScreenshotSyncCoordinator {
    enum Phase: Equatable {
        case idle
        case loading
        case ready
        case applying
        case stale
    }

    var phase: Phase = .idle
    var plan: ASCScreenshotSyncPlan? {
        didSet { outline = ASCScreenshotReviewOutline(sets: plan?.sets ?? []) }
    }
    /// The plan grouped for the review screen. Regrouped with the plan rather than computed on
    /// demand: the review body reads it several times per pass over up to 250 sets.
    private(set) var outline: ASCScreenshotReviewOutline = .empty
    var selectedSetIds: Set<String> = []
    var progressLabel = ""
    var result: ASCScreenshotSyncResult?
    var errorMessage: String?
    /// Set when the last build ended because the user cancelled, so callers can retreat
    /// quietly instead of reporting a failure.
    private(set) var wasCancelled = false
    /// The typed shape of the last failure, kept alongside the localized `errorMessage`.
    /// `errorMessage` is user-facing text built from row and locale labels, so it can never be
    /// transmitted — this is what `store_upload_failed` reports instead.
    private(set) var failure: StoreUploadFailure?

    private let service: AppStoreConnectScreenshotSyncService

    init(service: AppStoreConnectScreenshotSyncService? = nil) {
        self.service = service ?? .shared
    }

    var selectedSets: [ASCScreenshotSetDiff] {
        plan?.sets.filter { selectedSetIds.contains($0.id) } ?? []
    }

    var canApply: Bool {
        phase == .ready && !isExpired && !selectedSetIds.isEmpty && selectedSets.allSatisfy(\.canApply)
    }

    var isExpired: Bool {
        guard let plan else { return false }
        return plan.expiresAt <= Date()
    }

    var selectionTotals: ASCScreenshotSelectionTotals {
        ASCScreenshotSelectionTotals(sets: selectedSets)
    }

    var confirmationSummary: String {
        let totals = selectionTotals
        var parts = [
            String(localized: "\(totals.setCount) screenshot sets included."),
            String(localized: "\(totals.uploads) uploads, \(totals.removals) removals, and \(totals.moves) moves."),
            String(localized: "\(totals.preserved) unchanged screenshots will keep their App Store asset IDs.")
        ]
        if totals.capacityFirstDeletions > 0 {
            parts.append(String(localized: "\(totals.capacityFirstDeletions) screenshots must be removed first to stay within Apple's 10-screenshot limit."))
        }
        return parts.joined(separator: " ")
    }

    func build(appId: String, targets: [ASCUploadTarget], rows: [ScreenshotRow], source: some RowRenderSource, document: DocumentStamp?) async {
        phase = .loading
        errorMessage = nil
        result = nil
        wasCancelled = false
        if let oldPlan = plan { service.discardPlan(oldPlan.id) }
        plan = nil
        selectedSetIds = []
        do {
            let plan = try await service.buildPlan(
                appId: appId,
                targets: targets,
                rows: rows,
                source: source,
                document: document,
                progress: { [weak self] label in self?.progressLabel = label }
            )
            // The build may have finished after the user dismissed the review; adopting it here
            // would resurrect a plan `discard()` already tried to drop, leaking its temp folder.
            guard !Task.isCancelled else {
                service.discardPlan(plan.id)
                wasCancelled = true
                phase = .idle
                return
            }
            self.plan = plan
            selectAllChanged()
            phase = .ready
        } catch is CancellationError {
            wasCancelled = true
            phase = .idle
        } catch {
            errorMessage = error.localizedDescription
            phase = .idle
        }
    }

    func apply(document: DocumentStamp?, progress: @escaping (UploadProgress) -> Void) async {
        guard let plan else { return }
        if isExpired {
            phase = .stale
            errorMessage = ASCScreenshotSyncError.planExpired.localizedDescription
            return
        }
        phase = .applying
        errorMessage = nil
        failure = nil
        do {
            let result = try await service.apply(
                planId: plan.id,
                setIds: selectedSetIds,
                document: document,
                progress: progress
            )
            self.result = result
            if result.succeeded {
                phase = .ready
            } else {
                phase = .stale
                errorMessage = result.sets.compactMap(\.error).first
                // A per-set failure: the typed error was already stringified into the result,
                // so the shape is all that survives.
                failure = .unknown
            }
        } catch let error as ASCScreenshotSyncError {
            if case .planExpired = error { phase = .stale }
            else if case .staleProject = error { phase = .stale }
            else if case .staleRemote = error { phase = .stale }
            else { phase = .ready }
            errorMessage = error.localizedDescription
            failure = StoreUploadFailure.classify(error)
        } catch is CancellationError {
            phase = .ready
            errorMessage = String(localized: "Screenshot sync was cancelled. Changes already made in App Store Connect were not reverted.")
            failure = StoreUploadFailure(kind: .cancelled, errorCode: nil)
        } catch {
            phase = .ready
            errorMessage = error.localizedDescription
            failure = StoreUploadFailure.classify(error)
        }
    }

    func toggle(_ set: ASCScreenshotSetDiff, included: Bool) {
        guard set.isChanged, set.canApply else { return }
        if included { selectedSetIds.insert(set.id) }
        else { selectedSetIds.remove(set.id) }
    }

    /// Bulk selection stays a set of *leaf* set ids — `apply` rejects any id that isn't one of
    /// `plan.sets`, so these filter through the same predicate `toggle(_:included:)` enforces.
    func selectAllChanged() {
        selectedSetIds = Set(changedApplicableSets.map(\.id))
    }

    func deselectAll() {
        selectedSetIds = []
    }

    var changedApplicableSets: [ASCScreenshotSetDiff] {
        plan?.sets.filter { $0.isChanged && $0.canApply } ?? []
    }

    func discard() {
        if let plan { service.discardPlan(plan.id) }
        plan = nil
        selectedSetIds = []
        phase = .idle
        errorMessage = nil
        result = nil
    }

}
