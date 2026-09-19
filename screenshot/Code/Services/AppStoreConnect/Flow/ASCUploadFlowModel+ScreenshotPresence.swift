import Foundation
import os

extension ASCUploadFlowModel {
    // MARK: - "No screenshots yet" indicator

    /// Reads kept in flight at once. These GETs retry through `StoreRetryPolicy`, so an unbounded
    /// sweep of a 40-locale account risks the key's rate limit turning each refusal into three
    /// requests plus backoff.
    private static let presenceConcurrencyLimit = 5

    /// Restarts the sweep behind the per-locale "No screenshots yet" indicator. Nothing awaits it,
    /// so a slow or failed fetch costs the indicator rather than stalling the wizard.
    func startScreenshotPresenceLoad() {
        presenceTask?.cancel()
        presenceTask = Task { [weak self] in await self?.loadScreenshotPresence() }
    }

    /// Publishes each localization's result the moment it lands, rather than one set at the end.
    /// A 30-locale account across two versions is minutes of rate-limited GETs, and publishing once
    /// at the end meant the badges appeared long after the user had moved on — or never, because a
    /// cancelled sweep discarded every result it had already paid for.
    ///
    /// Results already known are deliberately kept across restarts: re-checking an id is cheap to
    /// display and the stale answer is almost always still right.
    func loadScreenshotPresence() async {
        var remaining = localizationsByVersionId.values.joined().map(\.id).makeIterator()
        await withTaskGroup(of: (String, Set<String>?).self) { group in
            for _ in 0..<Self.presenceConcurrencyLimit {
                guard let id = remaining.next() else { break }
                group.addTask { (id, await self.screenshotDisplayTypes(localizationId: id)) }
            }
            while let (id, displayTypes) = await group.next() {
                // nil is a failed read, which must stay "unknown" rather than become "has none".
                if let displayTypes {
                    screenshotDisplayTypesByLocalizationId[id] = displayTypes
                }
                guard !Task.isCancelled else {
                    group.cancelAll()
                    break
                }
                if let next = remaining.next() {
                    group.addTask { (next, await self.screenshotDisplayTypes(localizationId: next)) }
                }
            }
        }
    }

    /// The display types this localization has at least one uploaded screenshot for, or nil when
    /// the read failed. A set can exist with nothing in it, so a display type counts only when its
    /// set has a non-empty order — and failing to nil (rather than to an empty set) is what keeps a
    /// transient API error from manufacturing a "missing" badge next to a locale that is fine.
    private func screenshotDisplayTypes(localizationId: String) async -> Set<String>? {
        do {
            var populated: Set<String> = []
            for set in try await screenshotPresenceAPI.listScreenshotSets(localizationId: localizationId) {
                guard let displayType = set.attributes.screenshotDisplayType else { continue }
                if try await !screenshotPresenceAPI.listScreenshotOrder(setId: set.id).isEmpty {
                    populated.insert(displayType)
                }
            }
            return populated
        } catch {
            AppLogger.upload.error(
                "Screenshot presence failed for \(localizationId, privacy: .public): \(error, privacy: .public)"
            )
            return nil
        }
    }
}
