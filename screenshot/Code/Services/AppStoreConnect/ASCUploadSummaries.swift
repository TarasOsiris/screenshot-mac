import Foundation

/// What an upload / metadata save actually did, for the wizard's final screen.
nonisolated struct ASCUploadSummary {
    let appId: String?
    let appName: String
    let totalScreenshots: Int
    let localizationCount: Int
    let versionCount: Int
}

nonisolated struct ASCMetadataSaveSummary {
    let appId: String?
    let appName: String
    let versionCount: Int
    let localeCount: Int
    let fieldCount: Int
}
