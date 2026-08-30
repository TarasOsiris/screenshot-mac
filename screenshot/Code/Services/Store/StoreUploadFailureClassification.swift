import Foundation

/// Why a store upload failed, in a vocabulary safe to transmit.
///
/// Every case name is written out by hand rather than derived from the error, because the store
/// error enums carry `rowLabel`, `localeLabel` and `fileNames` as associated values —
/// `String(describing:)` on one of those would put a user's row names and file names into
/// analytics. The classifier reads the *shape* of the error and discards everything else.
///
/// Before this, `store_upload_failed` carried only `store` and `cancelled`, so five production
/// failures across two stores could not be told apart at all.
nonisolated enum StoreUploadFailureKind: String, CaseIterable {
    /// The store answered with an HTTP error. Pair with `http_status`.
    case httpError = "http_error"
    /// The request never reached the store (offline, DNS, TLS, timeout).
    case transport
    /// The store answered with a body we could not decode.
    case decodingFailed = "decoding_failed"
    /// Credentials missing, malformed, or rejected before any upload began.
    case auth
    /// A screenshot could not be rendered for upload.
    case renderFailed = "render_failed"
    /// Referenced image files were missing or unreadable on disk.
    case unreadableImages = "unreadable_images"
    /// Nothing was selected to upload.
    case nothingSelected = "nothing_selected"
    /// The prepared plan no longer matches the project or the store (expired, stale, superseded).
    case stalePlan = "stale_plan"
    case cancelled
    case unknown

    /// The kind and, when the store gave us one, its HTTP status.
    static func classify(_ error: Error) -> (kind: StoreUploadFailureKind, httpStatus: Int?) {
        if error is CancellationError { return (.cancelled, nil) }

        switch error {
        case let error as GooglePlayUploadError:
            switch error {
            case .renderFailed: return (.renderFailed, nil)
            case .unreadableImages: return (.unreadableImages, nil)
            case .noRowsSelected: return (.nothingSelected, nil)
            case .requestFailed(let context):
                let kind: StoreUploadFailureKind = context.httpStatus == nil ? .unknown : .httpError
                return (kind, context.httpStatus)
            }
        case let error as AppStoreConnectUploadError:
            switch error {
            case .renderFailed: return (.renderFailed, nil)
            case .noRowsSelected: return (.nothingSelected, nil)
            case .requestFailed(let context):
                let kind: StoreUploadFailureKind = context.httpStatus == nil ? .unknown : .httpError
                return (kind, context.httpStatus)
            }
        case let error as ASCScreenshotSyncError:
            switch error {
            case .planNotFound, .planExpired, .staleProject, .staleRemote, .invalidPlan:
                return (.stalePlan, nil)
            case .noSetsSelected: return (.nothingSelected, nil)
            case .unreadableImages: return (.unreadableImages, nil)
            }
        case let error as AppStoreConnectAPIError:
            switch error {
            case .httpError(let status, _): return (.httpError, status)
            case .transport, .invalidURL: return (.transport, nil)
            case .decodingFailed: return (.decodingFailed, nil)
            }
        case let error as GooglePlayAPIError:
            switch error {
            case .httpError(let status, _): return (.httpError, status)
            case .transport, .invalidURL: return (.transport, nil)
            case .decodingFailed: return (.decodingFailed, nil)
            }
        case is AppStoreConnectAuthError, is GooglePlayAuthError:
            return (.auth, nil)
        default:
            // URLSession's own offline/timeout errors, which never get wrapped when the failure
            // happens outside an API service.
            if (error as NSError).domain == NSURLErrorDomain { return (.transport, nil) }
            return (.unknown, nil)
        }
    }
}
