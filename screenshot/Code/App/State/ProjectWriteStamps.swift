import Foundation
import Synchronization

/// When a project was last read or written, so a reload can tell our own save from newer remote data.
/// Every stamp carries its project, so one project's never vouches for another after the active one changes.
final class ProjectWriteStamps {
    /// Ticks as each project write lands, so stamps follow disk order rather than completion-callback order.
    nonisolated private static let landedWrites = Atomic<Int>(0)

    /// The last load or *landed* save; a failed save stamping it would make reloads refuse newer remote data.
    private var landed: (projectId: UUID, date: Date, sequence: Int)?
    /// `translations.xcstrings` mod-date last read or written, so an external edit stands out from our own.
    private var catalog: (projectId: UUID, date: Date?)?
    private var inFlight: [UUID: (latest: Date, count: Int)] = [:]

    /// Taken right after a write lands, before its completion hops to the main actor.
    nonisolated static func nextLandedSequence() -> Int {
        landedWrites.add(1, ordering: .sequentiallyConsistent).newValue
    }

    /// Taken where a read is ordered behind the save queue, so the load reflects exactly these writes.
    nonisolated static func currentLandedSequence() -> Int {
        landedWrites.load(ordering: .sequentiallyConsistent)
    }

    func landed(for projectId: UUID) -> Date? {
        landed?.projectId == projectId ? landed?.date : nil
    }

    func forgetLanded() {
        landed = nil
    }

    /// What was read from disk; `sequence` is the landed writes the read reflects, nil meaning all so far.
    func recordLoad(_ projectId: UUID, modifiedAt: Date, catalogModified: Date?, sequence: Int? = nil) {
        landed = (projectId, modifiedAt, sequence ?? Self.currentLandedSequence())
        recordCatalogModified(projectId, at: catalogModified)
    }

    /// A write that reached disk before the current stamp's (a late completion) changes nothing.
    func recordWrite(_ projectId: UUID, modifiedAt: Date, catalogModified: Date?, sequence: Int) {
        if let landed, landed.projectId == projectId, landed.sequence >= sequence { return }
        recordLoad(projectId, modifiedAt: modifiedAt, catalogModified: catalogModified, sequence: sequence)
    }

    func catalogModified(for projectId: UUID) -> Date? {
        catalog?.projectId == projectId ? catalog?.date : nil
    }

    func recordCatalogModified(_ projectId: UUID, at date: Date?) {
        catalog = (projectId, date)
    }

    /// Includes writes still in flight: otherwise the file we are writing looks newer than memory and reloads.
    func known(for projectId: UUID) -> Date? {
        [landed(for: projectId), inFlight[projectId]?.latest].compactMap { $0 }.max()
    }

    func beginWrite(_ projectId: UUID, modifiedAt: Date) {
        let current = inFlight[projectId]
        inFlight[projectId] = (max(current?.latest ?? .distantPast, modifiedAt), (current?.count ?? 0) + 1)
    }

    func endWrite(_ projectId: UUID) {
        guard let current = inFlight[projectId] else { return }
        inFlight[projectId] = current.count > 1 ? (current.latest, current.count - 1) : nil
    }
}
