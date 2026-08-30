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
    /// The store answered with an HTTP error. Pair with `error_code`.
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
    /// The store reported a failure whose shape we could not read. Should stay rare — a rising
    /// count here means a case is missing above, not that uploads are mysteriously broken.
    case unknown
}

/// A classified upload failure, ready to report. A named type rather than a tuple because it is a
/// stored property on `ASCScreenshotSyncCoordinator` and crosses into two flow models — and
/// because it can carry the property assembly, which both stores otherwise duplicate.
nonisolated struct StoreUploadFailure: Equatable {
    let kind: StoreUploadFailureKind
    let errorCode: Int?

    static let unknown = StoreUploadFailure(kind: .unknown, errorCode: nil)

    /// The kind and, when the store gave us one, its HTTP status.
    static func classify(_ error: Error) -> StoreUploadFailure {
        if error is CancellationError { return StoreUploadFailure(kind: .cancelled, errorCode: nil) }

        switch error {
        case let error as GooglePlayUploadError:
            switch error {
            case .renderFailed: return StoreUploadFailure(kind: .renderFailed, errorCode: nil)
            case .unreadableImages: return StoreUploadFailure(kind: .unreadableImages, errorCode: nil)
            case .noRowsSelected: return StoreUploadFailure(kind: .nothingSelected, errorCode: nil)
            case .requestFailed(let context): return requestFailure(status: context.httpStatus)
            }
        case let error as AppStoreConnectUploadError:
            switch error {
            case .renderFailed: return StoreUploadFailure(kind: .renderFailed, errorCode: nil)
            case .noRowsSelected: return StoreUploadFailure(kind: .nothingSelected, errorCode: nil)
            case .requestFailed(let context): return requestFailure(status: context.httpStatus)
            }
        case let error as ASCScreenshotSyncError:
            switch error {
            case .planNotFound, .planExpired, .staleProject, .staleRemote, .invalidPlan:
                return StoreUploadFailure(kind: .stalePlan, errorCode: nil)
            case .noSetsSelected: return StoreUploadFailure(kind: .nothingSelected, errorCode: nil)
            case .unreadableImages: return StoreUploadFailure(kind: .unreadableImages, errorCode: nil)
            }
        case let error as AppStoreConnectAPIError:
            return apiFailure(status: error.httpStatus, isDecoding: error.isDecodingFailure)
        case let error as GooglePlayAPIError:
            return apiFailure(status: error.httpStatus, isDecoding: error.isDecodingFailure)
        case is AppStoreConnectAuthError, is GooglePlayAuthError:
            return StoreUploadFailure(kind: .auth, errorCode: nil)
        default:
            // URLSession's own offline/timeout errors, which never get wrapped when the failure
            // happens outside an API service.
            if (error as NSError).domain == NSURLErrorDomain {
                return StoreUploadFailure(kind: .transport, errorCode: (error as NSError).code)
            }
            return .unknown
        }
    }

    /// Both upload contexts null out `httpStatus` for every non-HTTP underlying error, so a nil
    /// here means the transport never got an answer — not that the shape is unknown.
    private static func requestFailure(status: Int?) -> StoreUploadFailure {
        guard let status else { return StoreUploadFailure(kind: .transport, errorCode: nil) }
        return StoreUploadFailure(kind: .httpError, errorCode: status)
    }

    private static func apiFailure(status: Int?, isDecoding: Bool) -> StoreUploadFailure {
        if let status { return StoreUploadFailure(kind: .httpError, errorCode: status) }
        return StoreUploadFailure(kind: isDecoding ? .decodingFailed : .transport, errorCode: nil)
    }

    /// The `store_upload_failed` payload. Lives here so the two flow models cannot drift on which
    /// keys this event may carry — which is a privacy decision, not just a formatting one.
    func report(store: String, cancelled: Bool) {
        var properties: [AnalyticsService.Property: Any] = [
            .store: store,
            .cancelled: cancelled,
            .result: kind.rawValue,
        ]
        if let errorCode { properties[.errorCode] = errorCode }
        AnalyticsService.capture(.storeUploadFailed, properties)
    }
}
