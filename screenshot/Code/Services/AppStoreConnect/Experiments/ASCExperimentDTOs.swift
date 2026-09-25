import Foundation

// Product page optimization (PPO v2): experiment → up to 3 treatments → per-locale localizations.

nonisolated struct ASCExperiment: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let attributes: Attributes

    struct Attributes: Decodable, Equatable, Sendable {
        let name: String?
        let platform: String?
        let state: String?
        let trafficProportion: Int?
        var startDate: String?
        var endDate: String?
    }

    static let maxTreatments = 3

    var name: String { attributes.name ?? "" }
    var ascPlatform: ASCPlatform? { attributes.platform.flatMap(ASCPlatform.init(rawValue:)) }
    var state: ASCExperimentState { ASCExperimentState(rawValue: attributes.state ?? "") ?? .unknown }

    var hasStarted: Bool { attributes.startDate != nil }

    /// Review has cleared it and nobody has started it yet.
    var canStart: Bool { (state == .accepted || state == .approved) && !hasStarted }

    var statusText: String {
        if hasStarted && attributes.endDate == nil && state == .approved { return String(localized: "Running") }
        return state.displayName
    }
}

nonisolated enum ASCExperimentState: String, Sendable {
    case prepareForSubmission = "PREPARE_FOR_SUBMISSION"
    case readyForReview = "READY_FOR_REVIEW"
    case waitingForReview = "WAITING_FOR_REVIEW"
    case inReview = "IN_REVIEW"
    case accepted = "ACCEPTED"
    case approved = "APPROVED"
    case rejected = "REJECTED"
    case completed = "COMPLETED"
    case stopped = "STOPPED"
    case unknown

    /// Treatments and their screenshots can still change, and it can be sent to review.
    var isEditable: Bool {
        switch self {
        case .prepareForSubmission, .readyForReview, .rejected: true
        default: false
        }
    }

    var displayName: String {
        switch self {
        case .prepareForSubmission: String(localized: "Prepare for Submission")
        case .readyForReview: String(localized: "Ready for Review")
        case .waitingForReview: String(localized: "Waiting for Review")
        case .inReview: String(localized: "In Review")
        case .accepted: String(localized: "Accepted")
        case .approved: String(localized: "Approved")
        case .rejected: String(localized: "Rejected")
        case .completed: String(localized: "Completed")
        case .stopped: String(localized: "Stopped")
        case .unknown: String(localized: "Unknown")
        }
    }
}

nonisolated struct ASCExperimentTreatment: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let attributes: Attributes

    struct Attributes: Decodable, Equatable, Sendable {
        let name: String?
    }

    var name: String { attributes.name ?? "" }
}

nonisolated struct ASCTreatmentLocalization: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let attributes: Attributes

    struct Attributes: Decodable, Equatable, Sendable {
        let locale: String
    }
}
