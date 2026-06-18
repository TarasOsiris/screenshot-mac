import Foundation

/// In-memory mock for Google Play demo mode. Edits and image uploads are local no-ops so
/// the upload wizard runs end-to-end without contacting Google. Mirrors the role of
/// `AppStoreConnectDemoData` (the Play API needs no project-derived catalog — the user
/// supplies the package name and the listing languages come from the project locales).
final class GooglePlayDemoData: @unchecked Sendable {
    static let shared = GooglePlayDemoData()

    private let lock = NSLock()
    private var idCounter = 0

    func insertEdit() -> GPEdit {
        lock.lock(); defer { lock.unlock() }
        idCounter += 1
        return GPEdit(id: "demo-edit-\(idCounter)", expiryTimeSeconds: nil)
    }

    func deleteAllImages(language _: String, imageType _: String) {}

    func uploadImage(language _: String, imageType _: String) -> GPImage {
        lock.lock(); defer { lock.unlock() }
        idCounter += 1
        return GPImage(id: "demo-image-\(idCounter)", url: nil, sha256: nil, sha1: nil)
    }
}
