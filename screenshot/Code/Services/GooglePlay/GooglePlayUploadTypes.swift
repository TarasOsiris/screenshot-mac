import Foundation

enum GooglePlayUploadError: StoreUploadErrorDescribing, LocalizedError {
    case renderFailed(rowLabel: String, imageTypeLabel: String, languageLabel: String, index: Int)
    case unreadableImages(rowLabel: String, languageLabel: String, fileNames: [String])
    case noRowsSelected
    case rowsRemoved
    case requestFailed(GPUploadFailureContext)

    var errorDescription: String? {
        switch self {
        case .renderFailed(let label, let imageTypeLabel, let languageLabel, let index):
            return String(localized: "Could not render screenshot \(index + 1) for \(label) (\(imageTypeLabel)) in \(languageLabel). Check that this row previews correctly in the editor, then try the upload again.")
        case .unreadableImages(let label, let languageLabel, let fileNames):
            if fileNames.count == 1 {
                return String(localized: "Could not read 1 image used by \(label) in \(languageLabel). Re-import the missing screenshot before uploading, or the upload would publish it as a blank area.")
            }
            return String(localized: "Could not read \(fileNames.count) images used by \(label) in \(languageLabel). Re-import the missing screenshots before uploading, or the upload would publish them as blank areas.")
        case .noRowsSelected:
            return String(localized: "No rows selected for upload.")
        case .rowsRemoved:
            return StoreUploadFailureText.rowsRemoved
        case .requestFailed(let context):
            return context.detailedMessage
        }
    }

    var summaryDescription: String {
        switch self {
        case .renderFailed(let label, _, let languageLabel, let index):
            return String(localized: "Could not render \(label) · \(languageLabel) · screenshot \(index + 1).")
        case .unreadableImages(let label, let languageLabel, _):
            return String(localized: "Missing images for \(label) · \(languageLabel).")
        case .noRowsSelected:
            return String(localized: "No rows selected for upload.")
        case .rowsRemoved:
            return StoreUploadFailureText.rowsRemoved
        case .requestFailed(let context):
            return context.summaryMessage
        }
    }

    var technicalDescription: String {
        switch self {
        case .renderFailed(let label, let imageTypeLabel, let languageLabel, let index):
            return [
                "Failure: render",
                "Row: \(label)",
                "Image type: \(imageTypeLabel)",
                "Language: \(languageLabel)",
                "Screenshot index: \(index + 1)"
            ].joined(separator: "\n")
        case .unreadableImages(let label, let languageLabel, let fileNames):
            return [
                "Failure: unreadable images",
                "Row: \(label)",
                "Language: \(languageLabel)",
                "Files: \(fileNames.joined(separator: ", "))"
            ].joined(separator: "\n")
        case .noRowsSelected:
            return "Failure: no rows selected"
        case .rowsRemoved:
            return "Failure: every planned row was removed from the project"
        case .requestFailed(let context):
            return context.technicalMessage
        }
    }
}

struct GPUploadLanguage {
    /// Project locale code used to render locale-specific text.
    let projectCode: String
    /// BCP-47 listing language Google Play expects.
    let playCode: String
    let label: String
}

struct GPUploadTarget: Identifiable {
    let id = UUID()
    let rowId: UUID
    let rowLabel: String
    let rowSize: CGSize
    let imageType: GPImageType
    let languages: [GPUploadLanguage]
    let templateCount: Int
}

/// A step of the Play publish. `diagnosticName` is stable English for breadcrumbs; `phrase`
/// completes the localized failure sentences.
nonisolated enum GPUploadOperation: Equatable {
    case openEdit
    case commitEdit
    case clearScreenshots(GPImageType)
    case uploadScreenshot(number: Int)

    var diagnosticName: String {
        switch self {
        case .openEdit: return "open a Play Console edit"
        case .commitEdit: return "commit the Play Console edit"
        case .clearScreenshots(let type): return "clear existing \(type.rawValue)"
        case .uploadScreenshot(let number): return "upload screenshot \(number)"
        }
    }

    var phrase: String {
        switch self {
        case .openEdit:
            return String(localized: "open a Play Console edit", comment: "Completes 'Google Play returned 500 while trying to …' and 'Could not … for <row> (<image type>) in <language>.'")
        case .commitEdit:
            return String(localized: "commit the Play Console edit", comment: "Completes 'Google Play returned 500 while trying to …' and 'Could not … for <row> (<image type>) in <language>.'")
        case .clearScreenshots(let type):
            return String(localized: "clear existing \(type.label) screenshots", comment: "Completes 'Google Play returned 500 while trying to …' and 'Could not … for <row> (<image type>) in <language>.' The placeholder is a Play image type such as 'Phone' or '7-inch tablet'.")
        case .uploadScreenshot(let number):
            return String(localized: "upload screenshot \(number)", comment: "Completes 'Google Play returned 500 while trying to …' and 'Could not … for <row> (<image type>) in <language>.' The placeholder is the screenshot's position in the row.")
        }
    }
}

nonisolated struct GPUploadFailureContext {
    let operation: GPUploadOperation
    let rowLabel: String
    let imageTypeLabel: String
    let languageLabel: String
    let languageCode: String
    let httpStatus: Int?
    let apiMessage: String?
    let originalMessage: String
    /// Set when the request failed in transit. Google Play never saw it, so the message must not
    /// blame what the request contained. Typed `URLError` rather than `Error` to keep this struct
    /// implicitly Sendable — it is thrown out of a `@MainActor` service.
    let transportError: URLError?

    init(operation: GPUploadOperation, target: GPUploadTarget, language: GPUploadLanguage, underlyingError: Error) {
        self.operation = operation
        self.rowLabel = target.rowLabel
        self.imageTypeLabel = target.imageType.label
        self.languageLabel = language.label
        self.languageCode = language.playCode

        if let apiError = underlyingError as? GooglePlayAPIError {
            switch apiError {
            case .httpError(let status, let message):
                self.httpStatus = status
                self.apiMessage = message
                self.originalMessage = "Google Play returned \(status): \(message)"
                self.transportError = nil
            case .transport(let error):
                self.httpStatus = nil
                self.apiMessage = nil
                self.originalMessage = String(localized: "Network request failed: \(error.localizedDescription)")
                self.transportError = error as? URLError
            default:
                self.httpStatus = nil
                self.apiMessage = nil
                self.originalMessage = apiError.localizedDescription
                self.transportError = nil
            }
        } else {
            self.httpStatus = nil
            self.apiMessage = nil
            self.originalMessage = underlyingError.localizedDescription
            self.transportError = nil
        }
    }

    var isConnectionFailure: Bool { transportError != nil }

    /// `repeatable: true` because the only caller clears the whole screenshot set before it
    /// uploads, so whatever a failed attempt left behind is wiped before the next one starts.
    func isWorthRetrying(under policy: StoreRetryPolicy) -> Bool {
        if let httpStatus { return policy.allowsRetry(status: httpStatus, repeatable: true) }
        guard let transportError else { return false }
        return policy.allowsRetry(transportError: transportError, repeatable: true)
    }

    private var isReviewFlagRejected: Bool {
        httpStatus == 400 && (apiMessage ?? originalMessage).localizedCaseInsensitiveContains("changesNotSentForReview")
    }

    var summaryMessage: String {
        if isReviewFlagRejected {
            return String(localized: "This app can't save an un-reviewed draft via the API — nothing was uploaded.")
        }
        if let httpStatus {
            return String(localized: "Google Play returned \(httpStatus) while trying to \(operation.phrase).", comment: "The last placeholder is an action such as 'upload screenshot 3'.")
        }
        if transportError?.code == .notConnectedToInternet {
            return String(localized: "No internet connection while trying to \(operation.phrase).", comment: "The placeholder is an action such as 'upload screenshot 3'.")
        }
        if isConnectionFailure {
            return String(localized: "The connection failed while trying to \(operation.phrase).", comment: "The placeholder is an action such as 'upload screenshot 3'.")
        }
        return String(localized: "Upload failed while trying to \(operation.phrase).", comment: "The placeholder is an action such as 'upload screenshot 3'.")
    }

    /// Every branch below is the same three parts: what failed, what to do about it, and what
    /// Google Play (or the transport) actually said.
    private func detail(_ advice: String) -> String {
        [
            String(localized: "Could not \(operation.phrase) for \(rowLabel) (\(imageTypeLabel)) in \(languageLabel).", comment: "Placeholders: an action such as 'upload screenshot 3', the row name, the Play image type, the listing language."),
            advice,
            String(localized: "Original response: \(originalMessage)")
        ].joined(separator: "\n\n")
    }

    var detailedMessage: String {
        if isReviewFlagRejected {
            return [
                String(localized: "Nothing was uploaded — the edit was discarded, so your listing is untouched."),
                String(localized: "Google Play won't hold this app's listing changes as an un-reviewed draft via the API (the Play Console's \"Save draft\" has no API equivalent for a published app). Committing would send the changes to review instead."),
                String(localized: "To upload: turn on Managed publishing in the Play Console (Publishing overview → Managed publishing) so reviewed changes are held until you publish, then enable \"Send changes to review\" here and upload again. Without Managed publishing, sending to review can make the changes go live after approval."),
                String(localized: "Original response: \(originalMessage)")
            ].joined(separator: "\n\n")
        }
        if httpStatus == 401 || httpStatus == 403 {
            return detail(String(localized: "Google Play rejected the request because the service account is not authorized for this app. In the Play Console, invite the service account under Users and permissions and grant it access to edit this app's store listing."))
        }
        if transportError?.code == .notConnectedToInternet {
            return detail(String(localized: "Your Mac lost its internet connection, so the request never reached Google Play. Nothing was published — the edit was discarded and your listing is unchanged. Reconnect and upload again."))
        }
        if isConnectionFailure {
            return detail(String(localized: "The request never completed, so Google Play never saw it. This is a connection problem, not something wrong with the package name, image type or language. Nothing was published — the edit was discarded and your listing is unchanged. Upload again when the connection is steady."))
        }
        if httpStatus == 404 {
            return detail(String(localized: "Google Play could not find the target. Check that the package name is correct and that \(languageCode) is an active store-listing language for this app."))
        }
        return detail(String(localized: "Google Play did not accept the request. Check the package name, image type, and language, then retry."))
    }

    var technicalMessage: String {
        [
            "Operation: \(operation.diagnosticName)",
            "Row: \(rowLabel)",
            "Image type: \(imageTypeLabel)",
            "Language: \(languageLabel) (\(languageCode))",
            "HTTP status: \(httpStatus.map(String.init) ?? "none")",
            "API message: \(apiMessage ?? "none")",
            "Original response: \(originalMessage)"
        ].joined(separator: "\n")
    }
}
