import Foundation

/// When the active project was last read or written, so a reload can tell our own save from newer remote data.
final class ProjectWriteStamps {
    /// The last load or *landed* save; a failed save stamping it would make reloads refuse newer remote data.
    var landed: Date?
    /// `translations.xcstrings` mod-date last read or written, so an external edit stands out from our own.
    var catalogModified: Date?

    private var inFlight: Date?
    private var inFlightCount = 0

    /// Includes writes still in flight: otherwise the file we are writing looks newer than memory and reloads.
    var known: Date? {
        [landed, inFlight].compactMap { $0 }.max()
    }

    func beginWrite(modifiedAt: Date) {
        inFlight = max(inFlight ?? .distantPast, modifiedAt)
        inFlightCount += 1
    }

    func endWrite() {
        inFlightCount -= 1
        if inFlightCount == 0 { inFlight = nil }
    }
}
