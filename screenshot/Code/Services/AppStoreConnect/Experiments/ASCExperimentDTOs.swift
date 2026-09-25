import Foundation

// Product page optimization (PPO v2): experiment → up to 3 treatments → per-locale localizations.

nonisolated struct ASCExperiment: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    var attributes: Attributes

    struct Attributes: Decodable, Equatable, Sendable {
        let name: String?
        let platform: String?
        var state: String?
        let trafficProportion: Int?
        var startDate: String?
        var endDate: String?
    }

    static let maxTreatments = 3

    var name: String { attributes.name ?? "" }
    var ascPlatform: ASCPlatform? { attributes.platform.flatMap(ASCPlatform.init(rawValue:)) }
    var state: ASCExperimentState { ASCExperimentState(rawValue: attributes.state ?? "") ?? .unknown }

    var hasStarted: Bool { attributes.startDate != nil }
    var hasEnded: Bool { attributes.endDate != nil || state == .completed || state == .stopped }
    var isRunning: Bool { hasStarted && !hasEnded }

    func with(state: ASCExperimentState) -> ASCExperiment {
        var copy = self
        copy.attributes.state = state.rawValue
        return copy
    }

    /// Review has cleared it and nobody has started it yet.
    var canStart: Bool { (state == .accepted || state == .approved) && !hasStarted }

    /// What to do with it next, for every state it can be in.
    var guidance: String {
        if state.isEditable {
            return String(localized: "Next, submit it for review. Apple reviews an experiment before it can start.")
        }
        if state == .waitingForReview || state == .inReview {
            return String(localized: "It's with App Review. To change it, remove it from review in App Store Connect, then upload again.")
        }
        if canStart {
            return String(localized: "It's approved. Start it when you're ready, or choose New Experiment to test other screenshots.")
        }
        if isRunning {
            return String(localized: "It's running. Results are in App Store Connect; choose New Experiment to test other screenshots.")
        }
        if hasEnded {
            return String(localized: "It has run, so its screenshots are final. Choose New Experiment to test new ones.")
        }
        return String(localized: "Its screenshots can't change in this state. Choose New Experiment to test new ones.")
    }

    var statusText: String {
        isRunning ? String(localized: "Running") : state.displayName
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

/// A review submission item, with the experiment it carries when requested via `include`.
nonisolated struct ASCReviewSubmissionItem: Decodable, Sendable {
    let id: String
    let relationships: Relationships?

    struct Relationships: Decodable, Sendable {
        let appStoreVersionExperimentV2: Relationship?
    }

    struct Relationship: Decodable, Sendable {
        let data: ASCResourceReference?
    }

    var experimentId: String? { relationships?.appStoreVersionExperimentV2?.data?.id }
}

nonisolated struct ASCTreatmentLocalization: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let attributes: Attributes

    struct Attributes: Decodable, Equatable, Sendable {
        let locale: String
    }
}
