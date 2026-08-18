import Observation

/// The iCloud monitor's upload/download progress, published for SwiftUI.
///
/// `ICloudMonitor` can't be observed directly: it is a `nonisolated final class` conforming to
/// `NSFilePresenter`, created and destroyed per project, and it mutates its status from a metadata
/// query callback. Observing it would put the observation registrar on a background queue and
/// break on every teardown. So the status is mirrored — this just gives the mirror a home of its
/// own instead of a slot on the document object, which is what let two settings screens hold the
/// whole `AppState` for one label each.
@Observable
final class ICloudSyncStatusModel {
    var status: SyncStatus = .idle
}
