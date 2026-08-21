import SwiftUI

/// Runtime state and flow for the interactive onboarding tour, split out of `AppState`. Holds a
/// weak back-reference to `AppState` for the row selection the tour drives.
@Observable
final class OnboardingCoachController {
    weak var app: AppState?

    /// Active step of the tour. `nil` when no tour is in progress.
    var step: OnboardingCoachStep?
    #if os(iOS)
    /// Set during the brief gap between coach marks so anchor views can prepare — e.g. scroll the
    /// upcoming anchor into view — before the next popover presents.
    var preparingStep: OnboardingCoachStep?
    @ObservationIgnored private var transitionTask: Task<Void, Never>?
    #endif
    /// When false, `end()` skips persisting `onboardingCompleted`. Used by the debug "Run Coach
    /// Tour" command so it can be re-run without consuming the real flag.
    @ObservationIgnored var persistsOnEnd = true
    /// Mirrors whether the Get Pro toolbar button is currently shown. The final coach step anchors
    /// on that button, so the tour skips it when Pro is already unlocked.
    @ObservationIgnored var proStepAvailable = true

    /// Starts the interactive onboarding tour at the first step.
    /// Pass `persistOnEnd: false` from debug entry points so re-running the
    /// tour doesn't consume the real `onboardingCompleted` flag.
    func start(persistOnEnd: Bool = true) {
        persistsOnEnd = persistOnEnd
        // The debug re-runs pass `persistOnEnd: false`; counting them would inflate the funnel
        // with our own walkthroughs.
        if persistOnEnd {
            AnalyticsService.capture(.onboardingStarted)
        }
        ensureRowSelected()
        setStep(.canvas)
    }

    /// Consumes the tour armed at first launch (no project existed then) and starts
    /// it. Callers report that the `.canvas` anchor is on screen and pass their
    /// size-class compactness — the iPad tour needs regular width, so at compact
    /// width the flag stays pending and the tour fires next time the canvas is
    /// visible full-width. Yields a runloop turn so the anchor is laid out before
    /// the popover shows.
    func startDeferredIfEligible(isCompactWidth: Bool) {
        guard let app, !app.isOpeningProject, !isCompactWidth else { return }
        guard OnboardingPersistence.isEditorCoachPending else { return }
        OnboardingPersistence.clearEditorCoachPending()
        Task { @MainActor in
            await Task.yield()
            start(persistOnEnd: true)
        }
    }

    #if os(iOS)
    /// Ends an in-flight tour when the editor leaves the screen (back to Projects,
    /// tab switch). Without this, a step set during the transition gap has no anchor,
    /// no popover presents, and the stale tour resurfaces on the next project open.
    func cancelActive() {
        let hadPendingTransition = transitionTask != nil || preparingStep != nil
        transitionTask?.cancel()
        transitionTask = nil
        preparingStep = nil
        guard step != nil || hadPendingTransition else { return }
        end(abandoned: true)
    }
    #endif

    /// Returns to the previous coach step, if any.
    func goBack() {
        guard let current = step, let previous = current.previous else { return }
        setStep(previous)
    }

    /// Advances to the next coach step, or ends the tour if on the last step.
    func advance() {
        guard let current = step else { return }
        guard let next = current.next else {
            end()
            return
        }
        // The Pro step anchors on the Get Pro button, which is gone once Pro is unlocked.
        if next == .pro, !proStepAvailable {
            end()
            return
        }
        // The inspector step anchors on row-scoped UI, which only renders
        // when a row is selected.
        if next == .inspector {
            ensureRowSelected()
        }
        setStep(next)
    }

    /// Ends the coach tour and persists onboarding completion (unless the tour
    /// was started with `persistOnEnd: false`).
    func end(abandoned: Bool = false) {
        let reachedStep = step.map(String.init(describing:)) ?? "none"
        setStep(nil)
        guard persistsOnEnd else { return }
        AnalyticsService.capture(
            abandoned ? .onboardingSkipped : .onboardingCompleted,
            [.source: "coach", .lastStep: reachedStep]
        )
        let defaults = UserDefaults.standard
        let key = OnboardingPersistence.completedKey
        if !defaults.bool(forKey: key) {
            defaults.set(true, forKey: key)
        }
    }

    private func setStep(_ newStep: OnboardingCoachStep?) {
        #if os(iOS)
        transitionTask?.cancel()
        transitionTask = nil
        // iPadOS silently drops a popover presented while the previous one is still
        // dismissing, and the next anchor may be scrolled offscreen. Clear the current
        // mark, let anchor views prepare (via preparingStep), then present once
        // the dismissal has settled.
        if let newStep, step != nil {
            step = nil
            preparingStep = newStep
            transitionTask = Task { @MainActor in
                try? await Task.sleep(for: OnboardingCoachStep.presentationSettleDelay)
                guard !Task.isCancelled else { return }
                preparingStep = nil
                withAnimation(.easeOut(duration: 0.2)) {
                    step = newStep
                }
            }
            return
        }
        preparingStep = nil
        #endif
        withAnimation(.easeOut(duration: 0.2)) {
            step = newStep
        }
    }

    private func ensureRowSelected() {
        guard let app, app.selectedRowId == nil, let first = app.rows.first else { return }
        app.selectRow(first.id)
    }
}
