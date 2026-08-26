import SwiftUI

/// Moved here from `Views/Toolbar/ZoomControls.swift`: `AppState` reached into a toolbar view
/// for these.
nonisolated enum ZoomConstants {
    static let min: CGFloat = 0.25
    static let max: CGFloat = 3.0
    static let step: CGFloat = 0.25
    static let presets: [CGFloat] = Array(stride(from: min, through: max, by: step))
}

/// Editor zoom: the level, its clamping, and the debounced write that restores it next launch.
///
/// Lived on `AppState` but has nothing to do with the document — nothing here is persisted with a
/// project, snapshotted for undo, or read by the save path. `ZoomControls` held the whole
/// `AppState` for it.
@Observable
@MainActor
final class ZoomController {
    /// Read by every visible row's body, so it must stay a plainly observed property — marking it
    /// `@ObservationIgnored` or hiding it behind a non-observable wrapper freezes the editor.
    private(set) var level: CGFloat = 1.0

    /// Pinch/scroll-wheel zoom writes at most ~30fps: an unthrottled gesture re-evaluates every
    /// visible row once per tick.
    @ObservationIgnored private let throttle = ContinuousApplyThrottle(interval: EditCoalescingTiming.continuousApplyInterval)
    @ObservationIgnored private var persistTask: Task<Void, Never>?
    /// Injected on the type, not per method: a half-injected seam lets a test control where the
    /// level is read from but not where it's written to.
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Restores the level the editor was left at, else the user's configured default. Called from
    /// `AppState.init` before the first `load()`, where it has always run.
    func restorePersistedLevel() {
        let last = defaults.double(forKey: AppSettingsKeys.lastZoomLevel)
        if last > 0 {
            level = last
            return
        }
        let configured = defaults.double(forKey: AppSettingsKeys.defaultZoomLevel)
        if configured > 0 { level = configured }
    }

    func set(_ newLevel: CGFloat, animated: Bool = true) {
        let clamped = min(ZoomConstants.max, max(ZoomConstants.min, newLevel))
        guard clamped != level else { return }
        if animated {
            withAnimation(.smooth(duration: 0.3)) {
                level = clamped
            }
        } else {
            level = clamped
        }
        persistTask?.cancel()
        persistTask = .delayed(0.3) { [defaults] in
            defaults.set(clamped, forKey: AppSettingsKeys.lastZoomLevel)
        }
    }

    /// Call `endContinuous()` when the gesture finishes so the final value is never dropped.
    func setContinuous(_ newLevel: CGFloat) {
        throttle.submit { [weak self] in
            self?.set(newLevel, animated: false)
        }
    }

    func endContinuous() {
        throttle.flush()
        throttle.reset()
    }

    /// Drop an in-flight gesture without flushing it — for a project switch or reset, where the
    /// pending value belongs to a document that is going away. Not the same as `endContinuous()`.
    func cancelContinuous() {
        throttle.reset()
    }

    func zoomIn() { set(level + ZoomConstants.step) }

    func zoomOut() { set(level - ZoomConstants.step) }

    func reset() {
        let configured = defaults.double(forKey: AppSettingsKeys.defaultZoomLevel)
        set(configured > 0 ? configured : AppSettingsKeys.Default.defaultZoomLevel)
        persistTask?.cancel()
        defaults.removeObject(forKey: AppSettingsKeys.lastZoomLevel)
    }

    /// Quit path: write the pending level synchronously rather than losing it with the run loop.
    func flushPendingPersist() {
        guard persistTask != nil else { return }
        persistTask?.cancel()
        persistTask = nil
        defaults.set(level, forKey: AppSettingsKeys.lastZoomLevel)
    }
}
