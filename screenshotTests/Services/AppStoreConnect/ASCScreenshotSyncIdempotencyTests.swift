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
    /// `.singleAttempt` by default so the existing tests see no retries; the rate-limit tests
    /// raise it to exercise the service's own `attempting` loops.
    var retryPolicy = StoreRetryPolicy.singleAttempt

    private(set) var reserveCount = 0
    private(set) var commitCount = 0
    private(set) var createSetCount = 0
    private(set) var deleteCount = 0
    private(set) var orderCount = 0
    private(set) var listSetsCount = 0
    /// Localization whose uploads should fail, to model a set that stops halfway. Keyed by
    /// localization rather than set id because set ids are minted here, not by the test.
    var failUploadsForLocalization: String?
    /// Rate-limit knobs: each fails its call the first N times, then behaves normally.
    var failCreateSetTimes = 0
    var failDeliveryPollTimes = 0
    var failCommitTimes = 0
    /// Status the knobs above throw. 429 is the case under test; 401 pins the non-transient path.
    var failureStatus = 429

    /// Preview downloads, which only the review screen needs. Asserted to be zero on the direct
    /// upload path.
    private(set) var downloadCount = 0
    /// How many delivery polls were actually refused, so a test can prove the loop stopped early.
    private(set) var deliveryPollFailures = 0

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
        listSetsCount += 1
        return try setLocalization
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
        // The set is recorded before the throw on purpose: that models the proxy rate-limiting a
        // POST the origin already processed, which is what the adopt path exists to survive.
        if failCreateSetTimes > 0 {
            failCreateSetTimes -= 1
            throw AppStoreConnectAPIError.httpError(status: failureStatus, message: "create refused")
        }
        return try Self.decode(#"{"id":"\#(id)","attributes":{"screenshotDisplayType":"\#(displayType)"}}"#)
    }

    func listScreenshots(setId: String, limit: Int, retryPolicy: StoreRetryPolicy?) async throws -> [ASCAppScreenshot] {
        try (members[setId] ?? []).map { try shot($0) }
    }

    func screenshot(id: String, retryPolicy: StoreRetryPolicy?) async throws -> ASCAppScreenshot {
        if failDeliveryPollTimes > 0 {
            failDeliveryPollTimes -= 1
            deliveryPollFailures += 1
            throw AppStoreConnectAPIError.httpError(status: failureStatus, message: "poll refused")
        }
        return try shot(id)
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
        if failCommitTimes > 0 {
            failCommitTimes -= 1
            throw AppStoreConnectAPIError.httpError(status: failureStatus, message: "commit refused")
        }
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

    /// A target whose row is gone is not work, so it must leave the denominator — a job's
    /// completion backstop compares the observed count against the total, and a plan that built
    /// perfectly used to be handed back as `failed`. It is reported rather than dropped silently.
    @Test func aTargetWhoseRowIsGoneLeavesTheDenominatorAndIsReported() async throws {
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
            progress: { last = $0 }
        )

        #expect(plan.sets.count == 1, "the target with no row produces no set")
        #expect(plan.issues.count == 1, "and says so, rather than leaving it to be inferred")
        let final = try #require(last)
        #expect(final.totalRenders == 1, "the vanished target is not in the denominator")
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

    // MARK: - Rate limiting

    private static let retryingPolicy = StoreRetryPolicy(
        maxAttempts: 3, baseDelay: .milliseconds(1), maxDelay: .milliseconds(2)
    )

    /// The reported bug: one 429 on a delivery poll used to abort the whole set, even though
    /// the bytes were already delivered. `verify`'s loop always tolerated this; this one didn't.
    @Test func deliveryPollSurvivesARateLimit() async throws {
        let api = FakeScreenshotSyncAPI()
        let service = AppStoreConnectScreenshotSyncService(
            api: api, isDemoMode: { false }, pollInterval: .milliseconds(1)
        )
        let (plan, stamp) = try await build(service)
        let setId = try #require(plan.sets.first?.id)
        api.failDeliveryPollTimes = 2

        let result = try await service.apply(planId: plan.id, setIds: [setId], document: stamp)

        #expect(result.succeeded)
        #expect(api.deliveryPollFailures == 2)
        #expect(api.reserveCount == 1, "a refused poll must not re-upload the screenshot")
        #expect(api.commitCount == 1)
    }

    /// Tolerating failures must not mean polling 30 times through a hard error — that would be a
    /// worse rate-limit story than the bug being fixed.
    @Test func deliveryPollStopsOnANonTransientError() async throws {
        let api = FakeScreenshotSyncAPI()
        let service = AppStoreConnectScreenshotSyncService(
            api: api, isDemoMode: { false }, pollInterval: .milliseconds(1)
        )
        let (plan, stamp) = try await build(service)
        let setId = try #require(plan.sets.first?.id)
        api.failureStatus = 401
        api.failDeliveryPollTimes = 99

        let result = try await service.apply(planId: plan.id, setIds: [setId], document: stamp)

        #expect(!result.succeeded)
        #expect(api.deliveryPollFailures == 1, "a 401 is a verdict, not a blip")
    }

    /// A commit writes fixed values, so the transport may repeat it — but only the commit.
    @Test func commitIsNotResentByReuploading() async throws {
        let api = FakeScreenshotSyncAPI()
        let service = AppStoreConnectScreenshotSyncService(
            api: api, isDemoMode: { false }, pollInterval: .milliseconds(1)
        )
        let (plan, stamp) = try await build(service)
        let setId = try #require(plan.sets.first?.id)
        api.failCommitTimes = 1

        let result = try await service.apply(planId: plan.id, setIds: [setId], document: stamp)

        #expect(!result.succeeded, "the fake's policy is .singleAttempt, so the commit is not retried here")
        #expect(api.reserveCount == 1, "a refused commit must not reserve a second screenshot")
    }

    /// A rate-limited create POST must not leave a second set behind: `verify` only ever inspects
    /// one set id, so a duplicate would be invisible and stay in the user's listing.
    @Test func createScreenshotSetAdoptsTheSetItAlreadyCreated() async throws {
        let api = FakeScreenshotSyncAPI()
        api.retryPolicy = Self.retryingPolicy
        let service = AppStoreConnectScreenshotSyncService(
            api: api, isDemoMode: { false }, pollInterval: .milliseconds(1)
        )
        let (plan, stamp) = try await build(service)
        let setId = try #require(plan.sets.first?.id)
        api.failCreateSetTimes = 1

        let result = try await service.apply(planId: plan.id, setIds: [setId], document: stamp)

        #expect(result.succeeded)
        #expect(api.createSetCount == 1, "the retry adopts rather than posting again")
        let sets = try await api.listScreenshotSets(localizationId: "loc-1", limit: 50)
        #expect(sets.count == 1, "exactly one set for the display type")
    }

    /// A create failure Apple will never accept must surface immediately, not burn the budget.
    @Test func nonTransientCreateFailureIsNotRetried() async throws {
        let api = FakeScreenshotSyncAPI()
        api.retryPolicy = Self.retryingPolicy
        let service = AppStoreConnectScreenshotSyncService(
            api: api, isDemoMode: { false }, pollInterval: .milliseconds(1)
        )
        let (plan, stamp) = try await build(service)
        let setId = try #require(plan.sets.first?.id)
        api.failureStatus = 409
        api.failCreateSetTimes = 99

        let result = try await service.apply(planId: plan.id, setIds: [setId], document: stamp)

        #expect(!result.succeeded)
        #expect(api.createSetCount == 1)
    }

    /// Without this the failure reaches PostHog as `unknown`, so the rate limit is invisible in
    /// exactly the funnel that would tell us whether it is still happening.
    @Test func perSetFailureCarriesTheTypedError() async throws {
        let api = FakeScreenshotSyncAPI()
        let service = AppStoreConnectScreenshotSyncService(
            api: api, isDemoMode: { false }, pollInterval: .milliseconds(1)
        )
        let (plan, stamp) = try await build(service)
        let setId = try #require(plan.sets.first?.id)
        api.failureStatus = 429
        api.failDeliveryPollTimes = 99

        let result = try await service.apply(planId: plan.id, setIds: [setId], document: stamp)

        let failed = try #require(result.sets.first { $0.state == .failed })
        #expect(failed.failure == StoreUploadFailure(kind: .httpError, errorCode: 429))
        #expect(failed.error?.contains("rate limiting") == true)
    }

    /// One response covers every display type of a localization, so asking once per display type
    /// was pure duplicated load on the account the rate limit is measured against.
    @Test func listScreenshotSetsIsFetchedOncePerLocalization() async throws {
        let api = FakeScreenshotSyncAPI()
        let service = AppStoreConnectScreenshotSyncService(api: api, isDemoMode: { false })
        let rowId = UUID()
        let stamp = DocumentStamp(projectId: UUID(), modifiedAt: Date())
        let localizations = [ASCUploadLocalization(id: "loc-1", label: "en-US", localeCode: "en")]

        _ = try await service.buildPlan(
            appId: "123",
            targets: [ASCDisplayType.iphone67, .ipadPro129M4].map {
                ASCUploadTarget(
                    versionId: "v1", versionLabel: "iOS · Version 1.0", rowId: rowId, rowLabel: "Row",
                    rowSize: CGSize(width: 60, height: 120), displayType: $0,
                    localizations: localizations, templateCount: 1
                )
            },
            rows: [makeRow(id: rowId)],
            source: StubRenderSource(),
            document: stamp,
            needsPreviews: false
        )

        #expect(api.listSetsCount == 1, "two display types share one localization listing")
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
