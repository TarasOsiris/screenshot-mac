import Foundation

@MainActor
protocol ASCExperimentAPI: AnyObject, Sendable {
    func listExperiments(appId: String) async throws -> [ASCExperiment]
    func experiment(id: String) async throws -> ASCExperiment
    func createExperiment(appId: String, platform: ASCPlatform, name: String, trafficProportion: Int) async throws -> ASCExperiment
    func startExperiment(id: String) async throws -> ASCExperiment
    func listTreatments(experimentId: String) async throws -> [ASCExperimentTreatment]
    func createTreatment(experimentId: String, name: String) async throws -> ASCExperimentTreatment
    func listTreatmentLocalizations(treatmentId: String) async throws -> [ASCTreatmentLocalization]
    func createTreatmentLocalization(treatmentId: String, locale: String) async throws -> ASCTreatmentLocalization
    func submitExperimentForReview(appId: String, platform: ASCPlatform, experimentId: String) async throws
}

enum ASCExperimentError: LocalizedError {
    case openReviewSubmission(platform: String)

    var errorDescription: String? {
        switch self {
        case .openReviewSubmission(let platform):
            String(localized: "App Store Connect already has an unsubmitted \(platform) review submission. Add the experiment to it there, or submit or remove it first, so nothing else is sent to review by accident.")
        }
    }
}

extension AppStoreConnectAPIService: ASCExperimentAPI {

    func listExperiments(appId: String) async throws -> [ASCExperiment] {
        if isDemoMode {
            await demoDelay()
            return ASCExperimentDemoStore.shared.experiments
        }
        let response: ASCListResponse<ASCExperiment> = try await get(
            "/v1/apps/\(appId)/appStoreVersionExperimentsV2?limit=50"
        )
        return response.data
    }

    func experiment(id: String) async throws -> ASCExperiment {
        if isDemoMode {
            await demoDelay()
            return try ASCExperimentDemoStore.shared.experiment(id: id)
        }
        let response: ASCSingleResponse<ASCExperiment> = try await get("/v2/appStoreVersionExperiments/\(id)")
        return response.data
    }

    func createExperiment(appId: String, platform: ASCPlatform, name: String, trafficProportion: Int) async throws -> ASCExperiment {
        if isDemoMode {
            await demoDelay()
            return ASCExperimentDemoStore.shared.createExperiment(platform: platform, name: name, trafficProportion: trafficProportion)
        }
        let body = ASCResourceCreate(data: .init(
            type: "appStoreVersionExperiments",
            attributes: [
                "name": AnyEncodable(name),
                "platform": AnyEncodable(platform.rawValue),
                "trafficProportion": AnyEncodable(trafficProportion),
            ],
            relationships: ["app": AnyEncodable(ASCRelationship.single(type: "apps", id: appId))]
        ))
        let response: ASCSingleResponse<ASCExperiment> = try await post("/v2/appStoreVersionExperiments", body: body)
        return response.data
    }

    func startExperiment(id: String) async throws -> ASCExperiment {
        if isDemoMode {
            await demoDelay()
            return try ASCExperimentDemoStore.shared.start(experimentId: id)
        }
        let body = ASCResourceUpdate(data: .init(
            type: "appStoreVersionExperiments",
            id: id,
            attributes: ["started": AnyEncodable(true)]
        ))
        let response: ASCSingleResponse<ASCExperiment> = try await patch(
            "/v2/appStoreVersionExperiments/\(id)",
            body: body,
            repeatable: true
        )
        return response.data
    }

    func listTreatments(experimentId: String) async throws -> [ASCExperimentTreatment] {
        if isDemoMode {
            await demoDelay()
            return ASCExperimentDemoStore.shared.treatments(experimentId: experimentId)
        }
        let response: ASCListResponse<ASCExperimentTreatment> = try await get(
            "/v2/appStoreVersionExperiments/\(experimentId)/appStoreVersionExperimentTreatments?limit=50"
        )
        return response.data
    }

    func createTreatment(experimentId: String, name: String) async throws -> ASCExperimentTreatment {
        if isDemoMode {
            await demoDelay()
            return ASCExperimentDemoStore.shared.createTreatment(experimentId: experimentId, name: name)
        }
        let body = ASCResourceCreate(data: .init(
            type: "appStoreVersionExperimentTreatments",
            attributes: ["name": AnyEncodable(name)],
            relationships: [
                "appStoreVersionExperimentV2": AnyEncodable(
                    ASCRelationship.single(type: "appStoreVersionExperiments", id: experimentId)
                ),
            ]
        ))
        let response: ASCSingleResponse<ASCExperimentTreatment> = try await post(
            "/v1/appStoreVersionExperimentTreatments",
            body: body
        )
        return response.data
    }

    func listTreatmentLocalizations(treatmentId: String) async throws -> [ASCTreatmentLocalization] {
        if isDemoMode {
            await demoDelay()
            return ASCExperimentDemoStore.shared.localizations(treatmentId: treatmentId)
        }
        let response: ASCListResponse<ASCTreatmentLocalization> = try await get(
            "/v1/appStoreVersionExperimentTreatments/\(treatmentId)/appStoreVersionExperimentTreatmentLocalizations?limit=200"
        )
        return response.data
    }

    func createTreatmentLocalization(treatmentId: String, locale: String) async throws -> ASCTreatmentLocalization {
        if isDemoMode {
            await demoDelay()
            return ASCExperimentDemoStore.shared.createLocalization(treatmentId: treatmentId, locale: locale)
        }
        let body = ASCResourceCreate(data: .init(
            type: "appStoreVersionExperimentTreatmentLocalizations",
            attributes: ["locale": AnyEncodable(locale)],
            relationships: [
                "appStoreVersionExperimentTreatment": AnyEncodable(
                    ASCRelationship.single(type: "appStoreVersionExperimentTreatments", id: treatmentId)
                ),
            ]
        ))
        let response: ASCSingleResponse<ASCTreatmentLocalization> = try await post(
            "/v1/appStoreVersionExperimentTreatmentLocalizations",
            body: body
        )
        return response.data
    }

    /// Never reuses an open submission: it may carry an app version the user isn't ready to send.
    func submitExperimentForReview(appId: String, platform: ASCPlatform, experimentId: String) async throws {
        if isDemoMode {
            await demoDelay()
            try ASCExperimentDemoStore.shared.submit(experimentId: experimentId)
            return
        }
        let open: ASCListResponse<ASCResourceReference> = try await get(
            "/v1/reviewSubmissions?filter%5Bapp%5D=\(appId)&filter%5Bplatform%5D=\(platform.rawValue)&filter%5Bstate%5D=READY_FOR_REVIEW&limit=5"
        )
        guard open.data.isEmpty else {
            throw ASCExperimentError.openReviewSubmission(platform: platform.displayName)
        }
        let submissionBody = ASCResourceCreate(data: .init(
            type: "reviewSubmissions",
            attributes: ["platform": AnyEncodable(platform.rawValue)],
            relationships: ["app": AnyEncodable(ASCRelationship.single(type: "apps", id: appId))]
        ))
        let submission: ASCSingleResponse<ASCResourceReference> = try await post("/v1/reviewSubmissions", body: submissionBody)

        let itemBody = ASCResourceCreate(data: .init(
            type: "reviewSubmissionItems",
            attributes: nil,
            relationships: [
                "reviewSubmission": AnyEncodable(
                    ASCRelationship.single(type: "reviewSubmissions", id: submission.data.id)
                ),
                "appStoreVersionExperimentV2": AnyEncodable(
                    ASCRelationship.single(type: "appStoreVersionExperiments", id: experimentId)
                ),
            ]
        ))
        let _: ASCSingleResponse<ASCResourceReference> = try await post("/v1/reviewSubmissionItems", body: itemBody)

        let submitBody = ASCResourceUpdate(data: .init(
            type: "reviewSubmissions",
            id: submission.data.id,
            attributes: ["submitted": AnyEncodable(true)]
        ))
        let _: ASCSingleResponse<ASCResourceReference> = try await patch(
            "/v1/reviewSubmissions/\(submission.data.id)",
            body: submitBody,
            repeatable: true
        )
    }
}

/// Demo-mode experiments; their screenshot sets live in `AppStoreConnectDemoData`, which resets this too.
nonisolated final class ASCExperimentDemoStore: @unchecked Sendable {
    static let shared = ASCExperimentDemoStore()

    private let lock = NSLock()
    private var experimentsById: [String: ASCExperiment] = [:]
    private var experimentOrder: [String] = []
    private var treatmentsByExperiment: [String: [ASCExperimentTreatment]] = [:]
    private var localizationsByTreatment: [String: [ASCTreatmentLocalization]] = [:]
    private var counter = 0

    private func nextId(_ prefix: String) -> String {
        counter += 1
        return "demo-\(prefix)-\(counter)"
    }

    func reset() {
        lock.withLock {
            experimentsById = [:]
            experimentOrder = []
            treatmentsByExperiment = [:]
            localizationsByTreatment = [:]
        }
    }

    func experiment(id: String) throws -> ASCExperiment {
        try lock.withLock {
            guard let experiment = experimentsById[id] else {
                throw AppStoreConnectAPIError.httpError(status: 404, message: "Experiment not found")
            }
            return experiment
        }
    }

    var experiments: [ASCExperiment] {
        lock.withLock { experimentOrder.compactMap { experimentsById[$0] } }
    }

    func createExperiment(platform: ASCPlatform, name: String, trafficProportion: Int) -> ASCExperiment {
        lock.withLock {
            let experiment = ASCExperiment(
                id: nextId("experiment"),
                attributes: .init(
                    name: name,
                    platform: platform.rawValue,
                    state: ASCExperimentState.prepareForSubmission.rawValue,
                    trafficProportion: trafficProportion
                )
            )
            experimentsById[experiment.id] = experiment
            experimentOrder.append(experiment.id)
            return experiment
        }
    }

    func treatments(experimentId: String) -> [ASCExperimentTreatment] {
        lock.withLock { treatmentsByExperiment[experimentId] ?? [] }
    }

    func createTreatment(experimentId: String, name: String) -> ASCExperimentTreatment {
        lock.withLock {
            let treatment = ASCExperimentTreatment(id: nextId("treatment"), attributes: .init(name: name))
            treatmentsByExperiment[experimentId, default: []].append(treatment)
            return treatment
        }
    }

    func localizations(treatmentId: String) -> [ASCTreatmentLocalization] {
        lock.withLock { localizationsByTreatment[treatmentId] ?? [] }
    }

    func createLocalization(treatmentId: String, locale: String) -> ASCTreatmentLocalization {
        lock.withLock {
            let localization = ASCTreatmentLocalization(id: nextId("tloc"), attributes: .init(locale: locale))
            localizationsByTreatment[treatmentId, default: []].append(localization)
            return localization
        }
    }

    /// Demo review is instant: a submitted experiment comes straight back accepted.
    func submit(experimentId: String) throws {
        try setState(.accepted, experimentId: experimentId)
    }

    func start(experimentId: String) throws -> ASCExperiment {
        try setState(.approved, experimentId: experimentId, startDate: ISO8601DateFormatter().string(from: Date()))
    }

    @discardableResult
    private func setState(_ state: ASCExperimentState, experimentId: String, startDate: String? = nil) throws -> ASCExperiment {
        try lock.withLock {
            guard let existing = experimentsById[experimentId] else {
                throw AppStoreConnectAPIError.httpError(status: 404, message: "Experiment not found")
            }
            var attributes = ASCExperiment.Attributes(
                name: existing.attributes.name,
                platform: existing.attributes.platform,
                state: state.rawValue,
                trafficProportion: existing.attributes.trafficProportion
            )
            attributes.startDate = startDate ?? existing.attributes.startDate
            let updated = ASCExperiment(id: existing.id, attributes: attributes)
            experimentsById[experimentId] = updated
            return updated
        }
    }
}
