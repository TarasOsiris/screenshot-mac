import Foundation

/// What a store listing already holds for one language, relative to the screenshot type a row
/// uploads as (an App Store display type, a Play image type).
enum StoreRemoteScreenshotStatus: Equatable {
    /// No screenshots of any type.
    case empty
    /// Screenshots exist, but none of this type.
    case missingForThisType
    case present(Int)

    /// Nil when either side isn't known yet, so nothing is claimed about the language.
    static func resolve(counts: [String: Int]?, assetKey: String?) -> Self? {
        guard let counts, let assetKey else { return nil }
        if let count = counts[assetKey], count > 0 { return .present(count) }
        return counts.values.contains { $0 > 0 } ? .missingForThisType : .empty
    }
}
