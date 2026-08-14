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
    var plan: ASCScreenshotSyncPlan?
    var selectedSetIds: Set<String> = []
    var progressLabel = ""
    var result: ASCScreenshotSyncResult?
    var errorMessage: String?
    /// Set when the last build ended because the user cancelled, so callers can retreat
    /// quietly instead of reporting a failure.
    private(set) var wasCancelled = false

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

    var confirmationSummary: String {
        let sets = selectedSets
        let uploads = sets.reduce(0) { $0 + $1.uploadCount }
        let removals = sets.reduce(0) { $0 + $1.removalCount }
        let moves = sets.reduce(0) { $0 + $1.moveCount }
        let preserved = sets.reduce(0) { $0 + $1.unchangedCount }
        let capacity = sets.reduce(0) { $0 + $1.capacityFirstDeletionCount }
        var parts = [
            String(localized: "\(sets.count) screenshot sets included."),
            String(localized: "\(uploads) uploads, \(removals) removals, and \(moves) moves."),
            String(localized: "\(preserved) unchanged screenshots will keep their App Store asset IDs.")
        ]
        if capacity > 0 {
            parts.append(String(localized: "\(capacity) screenshots must be removed first to stay within Apple's 10-screenshot limit."))
        }
        return parts.joined(separator: " ")
    }

    func build(appId: String, targets: [ASCUploadTarget], appState: AppState) async {
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
                appState: appState,
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
            selectedSetIds = Set(plan.sets.filter { $0.isChanged && $0.canApply }.map(\.id))
            phase = .ready
        } catch is CancellationError {
            wasCancelled = true
            phase = .idle
        } catch {
            errorMessage = error.localizedDescription
            phase = .idle
        }
    }

    func apply(appState: AppState, progress: @escaping (UploadProgress) -> Void) async {
        guard let plan else { return }
        if isExpired {
            phase = .stale
            errorMessage = ASCScreenshotSyncError.planExpired.localizedDescription
            return
        }
        phase = .applying
        errorMessage = nil
        do {
            let result = try await service.apply(
                planId: plan.id,
                setIds: selectedSetIds,
                appState: appState,
                progress: progress
            )
            self.result = result
            if result.succeeded {
                phase = .ready
            } else {
                phase = .stale
                errorMessage = result.sets.compactMap(\.error).first
            }
        } catch let error as ASCScreenshotSyncError {
            if case .planExpired = error { phase = .stale }
            else if case .staleProject = error { phase = .stale }
            else if case .staleRemote = error { phase = .stale }
            else { phase = .ready }
            errorMessage = error.localizedDescription
        } catch is CancellationError {
            phase = .ready
            errorMessage = String(localized: "Screenshot sync was cancelled. Changes already made in App Store Connect were not reverted.")
        } catch {
            phase = .ready
            errorMessage = error.localizedDescription
        }
    }

    func toggle(_ set: ASCScreenshotSetDiff, included: Bool) {
        guard set.isChanged, set.canApply else { return }
        if included { selectedSetIds.insert(set.id) }
        else { selectedSetIds.remove(set.id) }
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
