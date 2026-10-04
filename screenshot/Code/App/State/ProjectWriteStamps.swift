import Foundation

/// When a project was last read or written, so a reload can tell our own save from newer remote data.
/// Every stamp carries its project, so one project's never vouches for another after the active one changes.
final class ProjectWriteStamps {
    /// The last load or *landed* save; a failed save stamping it would make reloads refuse newer remote data.
    private var landed: (projectId: UUID, date: Date)?
    /// `translations.xcstrings` mod-date last read or written, so an external edit stands out from our own.
    private var catalog: (projectId: UUID, date: Date?)?
    private var inFlight: [UUID: (latest: Date, count: Int)] = [:]

    func landed(for projectId: UUID) -> Date? {
        landed?.projectId == projectId ? landed?.date : nil
    }

    func recordLanded(_ projectId: UUID, at date: Date) {
        landed = (projectId, date)
    }

    func forgetLanded() {
        landed = nil
    }

    /// What was just read from or written to disk; it replaces whatever was stamped before.
    func recordWrite(_ projectId: UUID, modifiedAt: Date, catalogModified: Date?) {
        recordLanded(projectId, at: modifiedAt)
        recordCatalogModified(projectId, at: catalogModified)
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
