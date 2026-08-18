import Foundation

/// The App Store Connect flow additionally remembers which store app this project uploads to, so
/// the app picker can preselect it next time.
@MainActor
protocol ASCUploadDocument: StoreUploadDocument {
    var savedASCAppId: String? { get }
    /// Records the chosen app against the active project. A no-op when there is no active project.
    func rememberASCAppId(_ appId: String)
}
