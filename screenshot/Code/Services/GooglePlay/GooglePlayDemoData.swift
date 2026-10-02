import Foundation

/// In-memory mock for Google Play demo mode. Edits and image uploads are local no-ops so
/// the upload wizard runs end-to-end without contacting Google. Mirrors the role of
/// `AppStoreConnectDemoData` (the Play API needs no project-derived catalog — the user
/// supplies the package name and the listing languages come from the project locales).
final class GooglePlayDemoData: @unchecked Sendable {
    static let shared = GooglePlayDemoData()

    /// Prefilled into the package field in demo mode. The wizard now verifies the package before
    /// building a plan, so without a plausible name to start from demo mode would open on an error.
    static let packageName = "com.example.demoapp"

    private let lock = NSLock()
    private var idCounter = 0

    func insertEdit() -> GPEdit {
        lock.lock(); defer { lock.unlock() }
        idCounter += 1
        return GPEdit(id: "demo-edit-\(idCounter)", expiryTimeSeconds: nil)
    }

    /// Images a demo upload has written, so the plan's badges reflect it on the next visit.
    private var uploadedCounts: [String: [String: Int]] = [:]

    func deleteAllImages(language: String, imageType: String) {
        lock.lock(); defer { lock.unlock() }
        uploadedCounts[language, default: [:]][imageType] = 0
    }

    func uploadImage(language: String, imageType: String) -> GPImage {
        lock.lock(); defer { lock.unlock() }
        idCounter += 1
        uploadedCounts[language, default: [:]][imageType, default: 0] += 1
        return GPImage(id: "demo-image-\(idCounter)", url: nil, sha256: nil, sha1: nil)
    }

    /// Cycles languages through the three states the plan's badge shows — some screenshots, none
    /// at all, and screenshots for another image type only — overlaid with what a demo upload wrote.
    func screenshotCounts(languages: [String]) -> [String: [String: Int]] {
        lock.lock(); defer { lock.unlock() }
        var result: [String: [String: Int]] = [:]
        for (index, language) in languages.enumerated() {
            var counts: [String: Int]
            switch index % 3 {
            case 0: counts = [GPImageType.phoneScreenshots.apiValue: 5, GPImageType.tenInchScreenshots.apiValue: 4]
            case 1: counts = [:]
            default: counts = [GPImageType.sevenInchScreenshots.apiValue: 3]
            }
            counts.merge(uploadedCounts[language] ?? [:]) { $1 }
            result[language] = counts
        }
        return result
    }
}
