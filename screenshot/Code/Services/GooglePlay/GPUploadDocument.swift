import Foundation

/// The Google Play flow remembers which Play listing this project uploads to, so the package
/// field can prefill next time.
@MainActor
protocol GPUploadDocument: StoreUploadDocument {
    var savedGooglePlayPackageName: String? { get }
    /// Records the package name against the active project; `nil` clears it. A no-op when there
    /// is no active project.
    func rememberGooglePlayPackageName(_ packageName: String?)
}
