import Foundation

/// Writes one screenshot set to App Store Connect — reserve, upload, wait for delivery, verify the
/// final order. Holds no state of its own: the plan cache and the idempotency ledger stay on
/// `AppStoreConnectScreenshotSyncService`, which owns one of these.
struct ASCScreenshotSetWriter {
    let api: any ASCScreenshotSyncAPI
    /// Read through a closure rather than the singleton directly: demo mode is a process-global
    /// that other suites toggle, and a test of the idempotency ledger must not be at their mercy.
    let isDemoMode: () -> Bool
    /// Base interval between delivery/verify polls. Injectable only so a test exercising a
    /// refused poll doesn't have to sleep through the real backoff.
    let pollInterval: Duration

    func upload(
        data: Data,
        fileName: String,
        setId: String,
        checksum: String,
        protectedRemoteIds: Set<String>
    ) async throws -> (id: String, delivery: ASCScreenshotDeliveryOutcome) {
        let reserved = try await reserve(
            setId: setId,
            fileName: fileName,
            fileSize: data.count,
            protectedRemoteIds: protectedRemoteIds
        )
        do {
            for operation in reserved.attributes.uploadOperations ?? [] {
                try Task.checkCancellation()
                try await api.uploadChunk(operation: operation, from: data)
            }
            try await api.commitScreenshot(id: reserved.id, md5Checksum: checksum)
        } catch {
            discardReservation(reserved.id)
            throw error
        }
        do {
            let delivery = try await waitForDelivery(screenshotId: reserved.id, expectedChecksum: checksum)
            return (reserved.id, delivery)
        } catch {
            // A committed upload Apple is merely slow to process is kept: the next sync matches it
            // by checksum instead of uploading it again. Only a verdict or a cancel removes it.
            if Self.discardsCommittedUpload(after: error) { discardReservation(reserved.id) }
            throw error
        }
    }

    /// An unstructured Task doesn't inherit cancellation, so this cleanup still runs when the
    /// failure *is* cancellation — otherwise the reservation is orphaned in the set.
    private func discardReservation(_ id: String) {
        Task { await deleteReservation(id) }
    }

    private static func discardsCommittedUpload(after error: Error) -> Bool {
        // A cancel mid-poll can surface as the transport's URLError rather than CancellationError.
        if error is CancellationError || Task.isCancelled { return true }
        switch error as? ASCScreenshotSyncError {
        case .deliveryStillProcessing?, nil: return false
        case .some: return true
        }
    }

    /// Reserving is the one upload step that is neither idempotent nor repeatable by itself,
    /// so its retry lives here rather than in the transport: a 5xx can still have created the
    /// reservation, and a duplicate left in the set makes `verify` reject the final order for
    /// its full 30 seconds. Sweeping between attempts is what makes the retry safe — which is
    /// also why the transport must not retry this POST underneath us.
    private func reserve(
        setId: String,
        fileName: String,
        fileSize: Int,
        protectedRemoteIds: Set<String>
    ) async throws -> ASCAppScreenshot {
        let policy = api.retryPolicy
        return try await policy.attempting {
            do {
                return try await api.reserveScreenshot(setId: setId, fileName: fileName, fileSize: fileSize)
            } catch {
                guard Self.isTransient(error, policy: policy) else { throw error }
                let apiError = error as? AppStoreConnectAPIError
                CrashReportingService.breadcrumb(
                    .upload,
                    "ASC reserve retry",
                    data: apiError?.httpStatus.map { ["status": $0] },
                    level: .warning
                )
                // A request that never reached Apple cannot have left a reservation behind.
                if StoreRetryPolicy.reachedServer(apiError?.transportError ?? error) {
                    await sweepOrphanedReservations(
                        setId: setId,
                        fileName: fileName,
                        protectedRemoteIds: protectedRemoteIds
                    )
                }
                throw StoreRetryPolicy.Retryable(underlying: error)
            }
        }
    }

    /// The transport must not repeat this POST: a duplicate set is invisible to `verify`, which
    /// only ever inspects one set id, and it stays in the user's real listing. It is repeatable
    /// here because the plan only reaches this branch with `remoteSetId == nil` — revalidation
    /// confirmed no set for this display type existed moments ago, so one that exists now is ours.
    func createOrAdoptScreenshotSet(
        parent: ASCScreenshotSetParent,
        displayType: ASCDisplayType
    ) async throws -> String {
        let policy = api.retryPolicy
        let value = displayType.appStoreConnectValue
        return try await policy.attempting {
            do {
                return try await api.createScreenshotSet(
                    parent: parent,
                    displayType: value
                ).id
            } catch let createError {
                guard Self.isTransient(createError, policy: policy) else { throw createError }
                let apiError = createError as? AppStoreConnectAPIError
                CrashReportingService.breadcrumb(
                    .upload,
                    "ASC create set retry",
                    data: apiError?.httpStatus.map { ["status": $0] },
                    level: .warning
                )
                // A request that never reached Apple cannot have created a set, so there is
                // nothing to adopt and repeating the POST is safe.
                guard StoreRetryPolicy.reachedServer(apiError?.transportError ?? createError) else {
                    throw StoreRetryPolicy.Retryable(underlying: createError)
                }
                // Being able to *ask* is the whole basis for repeating this POST. A refused
                // listing cannot tell a set we just created from one that never existed, and
                // guessing wrong leaves a duplicate `verify` never looks at.
                let sets: [ASCAppScreenshotSet]
                do {
                    sets = try await api.listScreenshotSets(parent: parent)
                } catch {
                    throw createError
                }
                if let existing = sets.first(where: { $0.attributes.screenshotDisplayType == value }) {
                    return existing.id
                }
                throw StoreRetryPolicy.Retryable(underlying: createError)
            }
        }
    }

    /// Deletes only what this reserve attempt could have left behind: same file name, not yet
    /// delivered, and not one of the screenshots the plan is keeping.
    private func sweepOrphanedReservations(
        setId: String,
        fileName: String,
        protectedRemoteIds: Set<String>
    ) async {
        guard let existing = try? await api.listScreenshots(setId: setId) else { return }
        for id in Self.orphanedReservationIds(
            in: existing,
            fileName: fileName,
            protectedRemoteIds: protectedRemoteIds
        ) {
            await deleteReservation(id)
        }
    }

    /// Failing to remove a reservation leaves it in the user's real App Store Connect set.
    private func deleteReservation(_ id: String) async {
        do {
            try await api.deleteScreenshot(id: id)
        } catch {
            CrashReportingService.report(.appStoreOrphanCleanupFailed, error: error)
        }
    }

    static func orphanedReservationIds(
        in screenshots: [ASCAppScreenshot],
        fileName: String,
        protectedRemoteIds: Set<String>
    ) -> [String] {
        screenshots.filter { shot in
            shot.attributes.fileName == fileName
                && !protectedRemoteIds.contains(shot.id)
                && shot.attributes.assetDeliveryState?.isComplete != true
        }.map(\.id)
    }

    /// `repeatable: true` for both callers, because each compensates before retrying: reserve
    /// sweeps the orphan it may have left, create adopts the set it may have made.
    private static func isTransient(_ error: Error, policy: StoreRetryPolicy) -> Bool {
        switch error as? AppStoreConnectAPIError {
        case .httpError(let status, _): policy.allowsRetry(status: status, repeatable: true)
        case .transport(let underlying): policy.allowsRetry(transportError: underlying, repeatable: true)
        case .invalidURL, .decodingFailed, .none: false
        }
    }

    @discardableResult
    private func waitForDelivery(
        screenshotId: String,
        expectedChecksum: String
    ) async throws -> ASCScreenshotDeliveryOutcome {
        if isDemoMode() { return .assumedComplete(screenshotId) }
        var lastError: Error?
        var failedPolls = 0
        for attempt in 0..<Self.deliveryPollLimit {
            try Task.checkCancellation()
            do {
                let screenshot = try await api.screenshot(id: screenshotId, retryPolicy: .singleAttempt)
                let delivery = screenshot.attributes.assetDeliveryState
                if delivery?.isComplete == true {
                    if let checksum = screenshot.attributes.sourceFileChecksum,
                       checksum.caseInsensitiveCompare(expectedChecksum) != .orderedSame {
                        throw ASCScreenshotSyncError.invalidPlan(
                            String(localized: "App Store Connect completed an upload with an unexpected checksum.")
                        )
                    }
                    return ASCScreenshotDeliveryOutcome(
                        screenshotId: screenshotId,
                        state: delivery?.state ?? "COMPLETE",
                        messages: delivery?.warnings?.compactMap { $0.message ?? $0.code } ?? []
                    )
                }
                if delivery?.isFailed == true {
                    let details = screenshot.attributes.assetDeliveryState?.errors?
                        .compactMap { $0.message ?? $0.code }
                        .joined(separator: ", ")
                    throw ASCScreenshotSyncError.invalidPlan(
                        details.map { String(localized: "App Store Connect rejected the screenshot: \($0)") }
                            ?? String(localized: "App Store Connect rejected the screenshot upload.")
                    )
                }
                lastError = nil
                failedPolls = 0
            } catch let error as ASCScreenshotSyncError {
                // Apple rejecting the asset is a verdict, not a blip — polling past it would
                // report "did not finish in time" for something it explicitly refused.
                throw error
            } catch {
                guard !Self.isPollFatal(error) else { throw error }
                lastError = error
                failedPolls += 1
                guard failedPolls < Self.maxConsecutivePollFailures else { throw error }
            }
            try await Task.sleep(for: deliveryPollDelay(attempt: attempt, failedPolls: failedPolls))
        }
        if let lastError { throw lastError }
        throw ASCScreenshotSyncError.deliveryStillProcessing
    }

    /// Apple routinely holds a committed screenshot in `UPLOAD_COMPLETE` for well over 30 s when
    /// it is busy, and giving up aborts the sync (the upload is kept for the next one). ~3.5 min:
    /// ten polls at the base interval, then one every 4×.
    private static let deliveryPollLimit = 60
    private static let deliveryFastPolls = 10

    private func deliveryPollDelay(attempt: Int, failedPolls: Int) -> Duration {
        if failedPolls > 0 { return pollDelay(failedPolls: failedPolls) }
        return attempt < Self.deliveryFastPolls ? pollInterval : pollInterval * 4
    }

    /// A poll that failed is evidence the account is being throttled, so polling again a second
    /// later makes the bucket worse. Tolerating failures without this turns one refused request
    /// per screenshot into thirty.
    private func pollDelay(failedPolls: Int) -> Duration {
        failedPolls == 0 ? pollInterval : min(pollInterval * pow(2.0, Double(failedPolls)), pollInterval * 8)
    }

    /// Enough to ride out a blip (~15s with the backoff above) and not enough to stall. The poll
    /// loops run 30–60 iterations, so tolerating a *sustained* refusal would sit for ~4 minutes
    /// behind a progress label that never moves — and a throttle that outlasts 15s is not going
    /// to clear inside this loop anyway. Failing hands the user the resumable path instead.
    private static let maxConsecutivePollFailures = 4

    /// A poll asks about state that is still settling, so almost anything is worth asking again —
    /// including the 404 or 409 a just-written relationship can answer with while App Store
    /// Connect catches up. Only a failure that will never clear ends the loop.
    private static func isPollFatal(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        switch error as? AppStoreConnectAPIError {
        case .httpError(let status, _): return status == 401 || status == 403
        case .transport: return false
        case .decodingFailed, .invalidURL, .none: return true
        }
    }

    func verify(
        setId: String,
        expectedIds: [String],
        expectedChecksums: [String]
    ) async throws -> Bool {
        if isDemoMode() { return true }
        var lastError: Error?
        var failedPolls = 0
        for attempt in 0..<30 {
            try Task.checkCancellation()
            do {
                let actual = try await orderedRemoteChecksums(setId: setId)
                if Self.matchesFinalOrder(
                    actual: actual,
                    expectedIds: expectedIds,
                    expectedChecksums: expectedChecksums
                ) {
                    return true
                }
                lastError = nil
                failedPolls = 0
            } catch {
                guard !Self.isPollFatal(error) else { throw error }
                lastError = error
                failedPolls += 1
                guard failedPolls < Self.maxConsecutivePollFailures else { throw error }
            }

            if attempt < 29 {
                try await Task.sleep(for: pollDelay(failedPolls: failedPolls))
            }
        }
        if let lastError { throw lastError }
        return false
    }

    static func matchesFinalOrder(
        actual: [(id: String, checksum: String)],
        expectedIds: [String],
        expectedChecksums: [String]
    ) -> Bool {
        actual.map(\.id) == expectedIds
            && actual.map { $0.checksum.lowercased() } == expectedChecksums.map { $0.lowercased() }
    }

    /// Only called from `verify`'s poll loop, which owns the retry budget.
    private func orderedRemoteChecksums(setId: String) async throws -> [(id: String, checksum: String)] {
        let screenshots = try await api.listScreenshots(setId: setId, retryPolicy: .singleAttempt)
        let order = try await api.listScreenshotOrder(setId: setId)
        let byId = Dictionary(uniqueKeysWithValues: screenshots.map { ($0.id, $0) })
        var actual: [(id: String, checksum: String)] = []
        for id in order {
            guard var screenshot = byId[id] else { continue }
            if screenshot.attributes.sourceFileChecksum == nil {
                screenshot = try await api.screenshot(id: id)
            }
            // A just-committed asset may not have published its checksum yet; report it as
            // pending so `verify` keeps retrying instead of comparing against a wrong value.
            actual.append((id, screenshot.attributes.sourceFileChecksum?.lowercased() ?? "pending:\(id)"))
        }
        return actual
    }
}
