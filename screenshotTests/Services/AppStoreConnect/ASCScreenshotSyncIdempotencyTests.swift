import AppKit
import Foundation
import MCP
@testable import Screenshot_Bro
import Testing

/// A tiny in-memory App Store Connect. Demo mode is not a substitute: it short-circuits the reads
/// but `apply` still issues every write, so this is the only way to assert that a retry uploads
/// nothing.
@MainActor
private final class FakeScreenshotSyncAPI: ASCScreenshotSyncAPI {
    let retryPolicy = StoreRetryPolicy.singleAttempt

    private(set) var reserveCount = 0
    private(set) var commitCount = 0
    private(set) var createSetCount = 0
    private(set) var deleteCount = 0
    private(set) var orderCount = 0
    /// Localization whose uploads should fail, to model a set that stops halfway. Keyed by
    /// localization rather than set id because set ids are minted here, not by the test.
    var failUploadsForLocalization: String?

    /// Preview downloads, which only the review screen needs. Asserted to be zero on the direct
    /// upload path.
    private(set) var downloadCount = 0

    private var nextSetId = 0
    private var nextShotId = 0
    private var setLocalization: [String: String] = [:]
    private var setDisplayType: [String: String] = [:]
    private var checksums: [String: String] = [:]
    private var members: [String: [String]] = [:]
    private var order: [String: [String]] = [:]

    var writeCount: Int { reserveCount + commitCount + createSetCount + deleteCount + orderCount }

    /// Put screenshots on the "store" before a build, so a plan has something to preserve or
    /// replace. Returns the set id.
    @discardableResult
    func seedExistingSet(localizationId: String, displayType: ASCDisplayType, checksums seeded: [String]) -> String {
        nextSetId += 1
        let setId = "seeded-set-\(nextSetId)"
        setLocalization[setId] = localizationId
        setDisplayType[setId] = displayType.appStoreConnectValue
        members[setId] = []
        order[setId] = []
        for checksum in seeded {
            nextShotId += 1
            let id = "seeded-shot-\(nextShotId)"
            checksums[id] = checksum
            members[setId, default: []].append(id)
            order[setId, default: []].append(id)
        }
        return setId
    }

    func listScreenshotSets(localizationId: String, limit: Int) async throws -> [ASCAppScreenshotSet] {
        try setLocalization
            .filter { $0.value == localizationId }
            .sorted { $0.key < $1.key }
            .map { setId, _ in
                try Self.decode(
                    #"{"id":"\#(setId)","attributes":{"screenshotDisplayType":"\#(setDisplayType[setId] ?? "")"}}"#
                )
            }
    }

    func createScreenshotSet(localizationId: String, displayType: String) async throws -> ASCAppScreenshotSet {
        createSetCount += 1
        nextSetId += 1
        let id = "set-\(nextSetId)"
        setLocalization[id] = localizationId
        setDisplayType[id] = displayType
        members[id] = []
        order[id] = []
        return try Self.decode(#"{"id":"\#(id)","attributes":{"screenshotDisplayType":"\#(displayType)"}}"#)
    }

    func listScreenshots(setId: String, limit: Int, retryPolicy: StoreRetryPolicy?) async throws -> [ASCAppScreenshot] {
        try (members[setId] ?? []).map { try shot($0) }
    }

    func screenshot(id: String, retryPolicy: StoreRetryPolicy?) async throws -> ASCAppScreenshot {
        try shot(id)
    }

    func listScreenshotOrder(setId: String) async throws -> [String] { order[setId] ?? [] }

    func setScreenshotOrder(setId: String, screenshotIds: [String]) async throws {
        orderCount += 1
        order[setId] = screenshotIds
    }

    func downloadScreenshotData(_ screenshot: ASCAppScreenshot, maxDimension: Int?) async throws -> Data {
        downloadCount += 1
        return Data()
    }

    func deleteScreenshot(id: String) async throws {
        deleteCount += 1
        checksums[id] = nil
        for (setId, ids) in members { members[setId] = ids.filter { $0 != id } }
        for (setId, ids) in order { order[setId] = ids.filter { $0 != id } }
    }

    func reserveScreenshot(setId: String, fileName: String, fileSize: Int) async throws -> ASCAppScreenshot {
        if let failing = failUploadsForLocalization, setLocalization[setId] == failing {
            throw AppStoreConnectAPIError.httpError(status: 500, message: "reserve exploded")
        }
        reserveCount += 1
        nextShotId += 1
        let id = "shot-\(nextShotId)"
        members[setId, default: []].append(id)
        order[setId, default: []].append(id)
        return try shot(id)
    }

    func uploadChunk(operation: ASCUploadOperation, from fileData: Data) async throws {}

    func commitScreenshot(id: String, md5Checksum: String) async throws {
        commitCount += 1
        checksums[id] = md5Checksum
    }

    private func shot(_ id: String) throws -> ASCAppScreenshot {
        let checksum = checksums[id].map { "\"sourceFileChecksum\":\"\($0)\"," } ?? ""
        return try Self.decode(
            #"{"id":"\#(id)","attributes":{\#(checksum)"fileName":"\#(id).png","assetDeliveryState":{"state":"COMPLETE"}}}"#
        )
    }

    private static func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }
}

@MainActor
private final class StubRenderSource: RowRenderSource {
    var localeState: LocaleState = .default
    var availableFontFamilySet: Set<String> = []
    func referencedImageFileNames(forRow row: ScreenshotRow, localeCode: String) -> Set<String> { [] }
    func loadFullResolutionImages(fileNames: Set<String>, cache: inout [String: NSImage]) -> [String: NSImage] { [:] }
}

@Suite(.serialized)
@MainActor
struct ASCScreenshotSyncIdempotencyTests {

    private func makeTarget(rowId: UUID, localizations: [String] = ["loc-1"]) -> ASCUploadTarget {
        ASCUploadTarget(
            versionId: "v1",
            versionLabel: "iOS · Version 1.0",
            rowId: rowId,
            rowLabel: "Row",
            rowSize: CGSize(width: 60, height: 120),
            displayType: .iphone67,
            localizations: localizations.map { ASCUploadLocalization(id: $0, label: "en-US", localeCode: "en") },
            templateCount: 1
        )
    }

    private func makeRow(id: UUID) -> ScreenshotRow {
        ScreenshotRow(id: id, templates: [ScreenshotTemplate()], templateWidth: 60, templateHeight: 120)
    }

    private func build(
        _ service: AppStoreConnectScreenshotSyncService,
        localizations: [String] = ["loc-1"],
        projectId: UUID = UUID(),
        modifiedAt: Date = Date(),
        strategy: ASCSyncStrategy = .reconcile,
        needsPreviews: Bool = true
    ) async throws -> (plan: ASCScreenshotSyncPlan, stamp: DocumentStamp) {
        let rowId = UUID()
        let row = makeRow(id: rowId)
        let stamp = DocumentStamp(projectId: projectId, modifiedAt: modifiedAt)
        let plan = try await service.buildPlan(
            appId: "123",
            targets: [makeTarget(rowId: rowId, localizations: localizations)],
            rows: [row],
            source: StubRenderSource(),
            document: stamp,
            strategy: strategy,
            needsPreviews: needsPreviews
        )
        return (plan, stamp)
    }

    // MARK: - Strategy

    /// The direct upload path builds to apply immediately, so the remote thumbnails the review
    /// screen would draw are pure cost — hundreds of image downloads on a many-locale project.
    @Test func theDirectPathDownloadsNoRemotePreviews() async throws {
        let api = FakeScreenshotSyncAPI()
        api.seedExistingSet(localizationId: "loc-1", displayType: .iphone67, checksums: ["deadbeef"])
        let service = AppStoreConnectScreenshotSyncService(api: api, isDemoMode: { false })

        _ = try await build(service, needsPreviews: false)

        #expect(api.downloadCount == 0)
    }

    /// The contrast, so the assertion above is about `needsPreviews` and not about the fake.
    @Test func theReviewPathStillDownloadsThem() async throws {
        let api = FakeScreenshotSyncAPI()
        api.seedExistingSet(localizationId: "loc-1", displayType: .iphone67, checksums: ["deadbeef"])
        let service = AppStoreConnectScreenshotSyncService(api: api, isDemoMode: { false })

        _ = try await build(service, needsPreviews: true)

        #expect(api.downloadCount == 1)
    }

    /// A job's completion backstop compares the *observed* count against the total, so a target
    /// skipped because its row is gone has to be reported and not merely counted locally —
    /// otherwise a plan that built perfectly is handed back as `failed`.
    @Test func aTargetWhoseRowIsGoneStillReportsItsRendersAsCompleted() async throws {
        let service = AppStoreConnectScreenshotSyncService(api: FakeScreenshotSyncAPI(), isDemoMode: { false })
        let presentId = UUID()
        var last: ASCSyncBuildProgress?

        let plan = try await service.buildPlan(
            appId: "123",
            targets: [
                makeTarget(rowId: presentId),
                // Built from a row list that no longer holds it: the document changed while the
                // build was awaiting App Store Connect.
                makeTarget(rowId: UUID(), localizations: ["loc-2"]),
            ],
            rows: [makeRow(id: presentId)],
            source: StubRenderSource(),
            document: DocumentStamp(projectId: UUID(), modifiedAt: Date()),
            needsPreviews: false,
            progress: { last = $0 }
        )

        #expect(plan.sets.count == 1, "the target with no row produces no set")
        let final = try #require(last)
        #expect(final.completedRenders == final.totalRenders)
    }

    @Test func replaceAllRemovesEveryRemoteAssetAndUploadsEveryLocalOne() async throws {
        let api = FakeScreenshotSyncAPI()
        api.seedExistingSet(localizationId: "loc-1", displayType: .iphone67, checksums: ["aaa", "bbb"])
        let service = AppStoreConnectScreenshotSyncService(api: api, isDemoMode: { false })

        let (plan, stamp) = try await build(service, strategy: .replaceAll, needsPreviews: false)
        let diff = try #require(plan.sets.first)
        #expect(diff.uploadCount == 1, "the one rendered template")
        #expect(diff.removalCount == 2)
        #expect(diff.unchangedCount == 0)

        let result = try await service.apply(planId: plan.id, setIds: [diff.id], document: stamp)

        #expect(result.succeeded)
        #expect(api.deleteCount == 2)
        #expect(api.reserveCount == 1)
        #expect(api.createSetCount == 0, "the seeded set is reused, not recreated")
    }

    /// Under `.reconcile` the same rendered bytes already on the store are left alone — which is
    /// exactly what Replace All gives up.
    @Test func reconcilePreservesAnExactMatchThatReplaceAllWouldReupload() async throws {
        let api = FakeScreenshotSyncAPI()
        let service = AppStoreConnectScreenshotSyncService(api: api, isDemoMode: { false })
        // Learn the checksum the renderer produces, then seed the store with it.
        let (probe, _) = try await build(service, needsPreviews: false)
        let checksum = try #require(probe.sets.first?.items.first?.checksum)
        service.discardPlan(probe.id)

        api.seedExistingSet(localizationId: "loc-1", displayType: .iphone67, checksums: [checksum])
        let (reconciled, _) = try await build(service, strategy: .reconcile, needsPreviews: false)
        let reconciledDiff = try #require(reconciled.sets.first)
        #expect(reconciledDiff.unchangedCount == 1)
        #expect(reconciledDiff.uploadCount == 0)
        service.discardPlan(reconciled.id)

        let (replaced, _) = try await build(service, strategy: .replaceAll, needsPreviews: false)
        let replacedDiff = try #require(replaced.sets.first)
        #expect(replacedDiff.unchangedCount == 0)
        #expect(replacedDiff.uploadCount == 1)
        #expect(replacedDiff.removalCount == 1)
    }

    /// A replace plan must stay resumable: `apply` revalidates by re-reading the remote and
    /// comparing `remoteFingerprint`, so the build has to have fetched the same detail the
    /// revalidation does. Skipping the checksum GETs or the order call here would fail as
    /// `staleRemote` on every run.
    @Test func aReplaceAllPlanSurvivesItsOwnRevalidation() async throws {
        let api = FakeScreenshotSyncAPI()
        api.seedExistingSet(localizationId: "loc-1", displayType: .iphone67, checksums: ["aaa"])
        let service = AppStoreConnectScreenshotSyncService(api: api, isDemoMode: { false })
        let (plan, stamp) = try await build(service, strategy: .replaceAll, needsPreviews: false)
        let setId = try #require(plan.sets.first?.id)

        let result = try await service.apply(planId: plan.id, setIds: [setId], document: stamp)

        #expect(result.succeeded, "a fingerprint mismatch would have thrown staleRemote")
    }

    @Test func replaceAllStepCountStillMatchesTheProgressDenominator() async throws {
        let api = FakeScreenshotSyncAPI()
        api.seedExistingSet(localizationId: "loc-1", displayType: .iphone67, checksums: ["aaa", "bbb"])
        let service = AppStoreConnectScreenshotSyncService(api: api, isDemoMode: { false })
        let (plan, stamp) = try await build(service, strategy: .replaceAll, needsPreviews: false)
        let diff = try #require(plan.sets.first)

        var lastTotal = 0
        _ = try await service.apply(
            planId: plan.id,
            setIds: [diff.id],
            document: stamp,
            progress: { lastTotal = $0.totalSteps }
        )

        #expect(lastTotal == AppStoreConnectScreenshotSyncService.applyStepCount([diff]))
    }

    @Test func applyUploadsOnceAndVerifies() async throws {
        let api = FakeScreenshotSyncAPI()
        let service = AppStoreConnectScreenshotSyncService(api: api, isDemoMode: { false })
        let (plan, stamp) = try await build(service)
        let setId = try #require(plan.sets.first?.id)

        let result = try await service.apply(planId: plan.id, setIds: [setId], document: stamp)

        #expect(result.succeeded)
        #expect(result.didMutate)
        #expect(api.reserveCount == 1)
        #expect(api.commitCount == 1)
        #expect(result.sets.first?.state == .succeeded)
        #expect(result.sets.first?.assetDeliveryStates == ["COMPLETE": 1])
    }

    /// The whole point: a client that timed out can retry the identical call and nothing is
    /// uploaded a second time.
    @Test func retryingAFullyAppliedPlanUploadsNothing() async throws {
        let api = FakeScreenshotSyncAPI()
        let service = AppStoreConnectScreenshotSyncService(api: api, isDemoMode: { false })
        let (plan, stamp) = try await build(service)
        let setId = try #require(plan.sets.first?.id)

        _ = try await service.apply(planId: plan.id, setIds: [setId], document: stamp)
        let writesAfterFirst = api.writeCount

        let retry = try await service.apply(planId: plan.id, setIds: [setId], document: stamp)

        #expect(api.writeCount == writesAfterFirst, "a retry must not touch App Store Connect")
        #expect(retry.succeeded)
        #expect(!retry.didMutate)
        #expect(retry.sets.count == 1)
        #expect(retry.sets.first?.state == .alreadyApplied)
        #expect(retry.sets.first?.alreadyApplied == true)
    }

    /// A retry works even though `apply` discards the plan on success — the ledger deliberately
    /// outlives the rendered bytes.
    @Test func retryAnswersEvenAfterThePlanWasDiscarded() async throws {
        let api = FakeScreenshotSyncAPI()
        let service = AppStoreConnectScreenshotSyncService(api: api, isDemoMode: { false })
        let (plan, stamp) = try await build(service)
        let setId = try #require(plan.sets.first?.id)

        _ = try await service.apply(planId: plan.id, setIds: [setId], document: stamp)
        #expect(service.plan(id: plan.id) == nil, "a successful apply discards the plan")

        let retry = try await service.apply(planId: plan.id, setIds: [setId], document: stamp)
        #expect(retry.sets.first?.state == .alreadyApplied)
    }

    @Test func resumeAttemptsOnlyTheSetThatDidNotLand() async throws {
        let api = FakeScreenshotSyncAPI()
        // Both display-type sets must already exist on the store. If `apply` has to *create* one,
        // the remote no longer matches what the plan was built against and the resume correctly
        // refuses it as a partially applied set — see the test below.
        api.seedExistingSet(localizationId: "loc-1", displayType: .iphone67, checksums: [])
        api.seedExistingSet(localizationId: "loc-2", displayType: .iphone67, checksums: [])
        let service = AppStoreConnectScreenshotSyncService(api: api, isDemoMode: { false })
        let (plan, stamp) = try await build(service, localizations: ["loc-1", "loc-2"])
        #expect(plan.sets.count == 2)
        let ids = Set(plan.sets.map(\.id))

        // Fail everything targeting the second locale.
        api.failUploadsForLocalization = "loc-2"
        let first = try await service.apply(planId: plan.id, setIds: ids, document: stamp)
        #expect(!first.succeeded)
        let landed = try #require(first.sets.first { $0.state == .succeeded }).id

        api.failUploadsForLocalization = nil
        let reservesBefore = api.reserveCount
        let resumed = try await service.apply(planId: plan.id, setIds: ids, document: stamp)

        #expect(resumed.sets.first { $0.id == landed }?.state == .alreadyApplied)
        #expect(api.reserveCount == reservesBefore + 1, "only the set that failed should be retried")
    }

    /// The other half of 045dfdd6's contract: when the earlier attempt *did* change the remote —
    /// here by creating a screenshot set the plan was not built against — the resume refuses
    /// rather than writing against a stale plan, and says so as `partiallyAppliedSet` instead of
    /// blaming the user for editing their listing.
    @Test func resumeRefusesASetWhoseRemoteTheEarlierAttemptChanged() async throws {
        let api = FakeScreenshotSyncAPI()
        let service = AppStoreConnectScreenshotSyncService(api: api, isDemoMode: { false })
        let (plan, stamp) = try await build(service, localizations: ["loc-1"])
        let setId = try #require(plan.sets.first?.id)

        // No seeded set, so `apply` creates one, then the upload into it fails.
        api.failUploadsForLocalization = "loc-1"
        _ = try? await service.apply(planId: plan.id, setIds: [setId], document: stamp)
        api.failUploadsForLocalization = nil

        await #expect(throws: ASCScreenshotSyncError.self) {
            _ = try await service.apply(planId: plan.id, setIds: [setId], document: stamp)
        }
    }

    @Test func retainedPlanSurvivesADiscardAndDropsOnRelease() async throws {
        let api = FakeScreenshotSyncAPI()
        let service = AppStoreConnectScreenshotSyncService(api: api, isDemoMode: { false })
        let (plan, _) = try await build(service)

        service.retainPlan(plan.id)
        service.discardPlan(plan.id)
        #expect(service.plan(id: plan.id) != nil, "a retained plan must survive the wizard discarding it")

        service.releasePlan(plan.id)
        #expect(service.plan(id: plan.id) == nil, "the deferred discard lands on release")
    }

    /// End-to-end through the tool, because the bug was in the *job wrapper*, not the service: the
    /// ledger short-circuit returns before emitting any progress, so a wholly already-applied
    /// retry finished at 0 of N and the completion backstop downgraded it to `failed` — reporting
    /// failure for the one path guaranteed to be safe.
    @Test func anIdempotentRetryThroughTheToolReportsSucceeded() async throws {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        // Demo mode only to satisfy `requireASCConfigured`; the service stays non-demo, so the
        // writes under test still reach the fake rather than being short-circuited.
        let credentials = AppStoreConnectCredentialsStore.shared
        let originalDemoMode = credentials.isDemoMode
        credentials.isDemoMode = true
        defer { credentials.isDemoMode = originalDemoMode }

        let projectId = try #require(state.activeProject?.id)
        let api = FakeScreenshotSyncAPI()
        let service = AppStoreConnectScreenshotSyncService(api: api, isDemoMode: { false })
        let executor = MCPToolExecutor(state: state, jobs: MCPJobStore(), screenshotSync: service)
        // The plan must name a real project, because apply resolves a checkout from it.
        let (plan, _) = try await build(
            service,
            projectId: projectId,
            modifiedAt: state.documentStamp?.modifiedAt ?? Date()
        )
        let setId = try #require(plan.sets.first?.id)

        let arguments: [String: Value] = [
            "plan_id": .string(plan.id),
            "set_ids": .array([.string(setId)]),
            "confirm": .bool(true),
            "mode": .string("sync"),
        ]
        let first = await executor.call(name: "apply_app_store_screenshot_sync", arguments: arguments)
        #expect(first.isError != true, "unexpected error: \(first.content)")

        let writesAfterFirst = api.writeCount
        let retry = await executor.call(name: "apply_app_store_screenshot_sync", arguments: arguments)
        #expect(retry.isError != true, "unexpected error: \(retry.content)")
        #expect(api.writeCount == writesAfterFirst, "a retry must not touch App Store Connect")

        guard case .text(let json, _, _) = retry.content.first else {
            Issue.record("expected text content")
            return
        }
        let envelope = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        #expect(envelope["phase"] as? String == "succeeded", "a safe retry must not report failure")
    }

    @Test func applyStepCountMatchesTheProgressDenominator() async throws {
        let api = FakeScreenshotSyncAPI()
        let service = AppStoreConnectScreenshotSyncService(api: api, isDemoMode: { false })
        let (plan, stamp) = try await build(service)
        let expected = AppStoreConnectScreenshotSyncService.applyStepCount(plan.sets)

        var lastTotal = 0
        _ = try await service.apply(planId: plan.id, setIds: Set(plan.sets.map(\.id)), document: stamp) {
            lastTotal = $0.totalSteps
        }
        #expect(lastTotal == expected, "the sizing estimate and the progress denominator must not drift")
    }
}
