import Foundation

/// The store an API error came from. It only supplies the message that names the store, so each
/// store keeps its own translated string.
nonisolated protocol StoreAPIOrigin {
    static func httpErrorDescription(status: Int, message: String) -> String
}

/// What failure classification needs from either store's API error without knowing which store.
nonisolated protocol StoreAPIFailure: Error {
    var httpStatus: Int? { get }
    var isDecodingFailure: Bool { get }
}

/// One error shape for both store APIs. Each store names its own specialization
/// (`AppStoreConnectAPIError`, `GooglePlayAPIError`), so `as?` still tells the stores apart.
nonisolated enum StoreAPIError<Origin: StoreAPIOrigin>: StoreAPIFailure, LocalizedError {
    case invalidURL
    case httpError(status: Int, message: String)
    case decodingFailed(Error)
    case transport(Error)

    init(_ error: StoreHTTPError) {
        switch error {
        case .invalidURL: self = .invalidURL
        case .nonHTTPResponse: self = .httpError(status: -1, message: "Non-HTTP response")
        case .status(let status, let message): self = .httpError(status: status, message: message ?? "HTTP \(status)")
        case .transport(let underlying): self = .transport(underlying)
        }
    }

    var httpStatus: Int? {
        if case let .httpError(status, _) = self { return status }
        return nil
    }

    var isDecodingFailure: Bool {
        if case .decodingFailed = self { return true }
        return false
    }

    var transportError: Error? {
        if case let .transport(underlying) = self { return underlying }
        return nil
    }

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return String(localized: "Invalid request URL.")
        case .httpError(let status, let message):
            return Origin.httpErrorDescription(status: status, message: message)
        case .decodingFailed(let error):
            return String(localized: "Response decoding failed: \(error.localizedDescription)")
        case .transport(let error):
            return error.localizedDescription
        }
    }
}
