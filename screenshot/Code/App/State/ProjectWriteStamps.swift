import Foundation

/// When the active project was last read or written, so a reload can tell our own save from newer
/// remote data. Reset on every project load via `applyProjectData`.
final class ProjectWriteStamps {
    /// `modifiedAt` of the last load or *landed* save; a failed save must never stamp it, or
    /// `reloadICloudFromDisk` would refuse genuinely newer remote data forever.
    var landed: Date?
    /// `translations.xcstrings` mod-date last read or written, so an external (Xcode/translator)
    /// edit can be told apart from our own dual-write on re-activation.
    var catalogModified: Date?

    private var inFlight: Date?
    private var inFlightCount = 0

    /// The newest local write we know of, landed or still in flight. Without the in-flight half,
    /// the file we are in the middle of writing looks newer than memory and triggers a reload —
    /// which clears the undo stack and drops in-flight edits.
    var known: Date? {
        switch (landed, inFlight) {
        case let (landed?, inFlight?): max(landed, inFlight)
        case let (landed?, nil): landed
        case let (nil, inFlight?): inFlight
        case (nil, nil): nil
        }
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
