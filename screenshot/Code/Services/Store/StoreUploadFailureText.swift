import Foundation

/// An upload error that can describe itself twice: a one-line summary for the inline banner,
/// and the full technical text for the "Details" sheet. Both store upload errors already had
/// these two members; naming the shape lets the summary/details composition be written once.
nonisolated protocol StoreUploadErrorDescribing: Error {
    var summaryDescription: String { get }
    var technicalDescription: String { get }
}

/// Composes the two strings the upload wizards show when an upload fails. The App Store Connect
/// and Google Play flows each had their own copy of this, differing only in which context lines
/// they contributed.
nonisolated enum StoreUploadFailureText {

    /// The inline banner line.
    static func summary(for error: Error) -> String {
        if let described = error as? any StoreUploadErrorDescribing {
            return described.summaryDescription
        }
        return String(localized: "Upload failed: \(error.localizedDescription)")
    }

    /// The Details sheet: the error, then any store-specific context the caller supplies
    /// (the app and its versions, or the package name), then the technical text when the
    /// error carries one.
    static func details(for error: Error, context: [String] = []) -> String {
        var sections: [String] = [error.localizedDescription]
        sections.append(contentsOf: context)
        if let described = error as? any StoreUploadErrorDescribing {
            sections.append("Technical details:\n\(described.technicalDescription)")
        }
        return sections.joined(separator: "\n\n")
    }
}
