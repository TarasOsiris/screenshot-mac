import SwiftUI

extension AppState {
    /// Starts the interactive onboarding tour at the first step.
    /// Pass `persistOnEnd: false` from debug entry points so re-running the
    /// tour doesn't consume the real `onboardingCompleted` flag.
    func startCoach(persistOnEnd: Bool = true) {
        coachPersistsOnEnd = persistOnEnd
        ensureRowSelected()
        setCoachStep(.canvas)
    }

    /// Consumes a tour deferred from when the welcome flow closed (no project was
    /// open then) and starts it. Callers report that the `.canvas` anchor is on
    /// screen and pass their size-class compactness — the iPad tour needs regular
    /// width, so at compact width the flags stay pending and the tour fires next
    /// time the canvas is visible full-width. Yields a runloop turn so the anchor
    /// is laid out before the popover shows.
    func startDeferredCoachIfEligible(isCompactWidth: Bool) {
        guard !isOpeningProject else { return }
        var pendingPersist = pendingCoachPersistOnEnd
        #if os(iOS)
        guard OnboardingCoachStep.tourSupportedOnDevice, !isCompactWidth else { return }
        // The persisted flag covers a relaunch between welcome and first project open.
        if pendingPersist == nil, OnboardingPersistence.isEditorCoachPending {
            pendingPersist = true
        }
        #endif
        guard let persist = pendingPersist else { return }
        pendingCoachPersistOnEnd = nil
        OnboardingPersistence.clearEditorCoachPending()
        Task { @MainActor in
            await Task.yield()
            startCoach(persistOnEnd: persist)
        }
    }

    #if os(iOS)
    /// Ends an in-flight tour when the editor leaves the screen (back to Projects,
    /// tab switch). Without this, a step set during the transition gap has no anchor,
    /// no popover presents, and the stale tour resurfaces on the next project open.
    func cancelActiveCoach() {
        let hadPendingTransition = coachTransitionTask != nil || coachPreparingStep != nil
        coachTransitionTask?.cancel()
        coachTransitionTask = nil
        coachPreparingStep = nil
        guard coachStep != nil || hadPendingTransition else { return }
        endCoach()
    }
    #endif

    /// Returns to the previous coach step, if any.
    func goBackInCoach() {
        guard let current = coachStep, let previous = current.previous else { return }
        setCoachStep(previous)
    }

    /// Advances to the next coach step, or ends the tour if on the last step.
    func advanceCoach() {
        guard let current = coachStep else { return }
        guard let next = current.next else {
            endCoach()
            return
        }
        // The Pro step anchors on the Get Pro button, which is gone once Pro is unlocked.
        if next == .pro, !coachProStepAvailable {
            endCoach()
            return
        }
        // The inspector step anchors on row-scoped UI, which only renders
        // when a row is selected.
        if next == .inspector {
            ensureRowSelected()
        }
        setCoachStep(next)
    }

    /// Ends the coach tour and persists onboarding completion (unless the tour
    /// was started with `persistOnEnd: false`).
    func endCoach() {
        setCoachStep(nil)
        guard coachPersistsOnEnd else { return }
        let defaults = UserDefaults.standard
        let key = OnboardingPersistence.completedKey
        if !defaults.bool(forKey: key) {
            defaults.set(true, forKey: key)
        }
    }

    private func setCoachStep(_ step: OnboardingCoachStep?) {
        #if os(iOS)
        coachTransitionTask?.cancel()
        coachTransitionTask = nil
        // iPadOS silently drops a popover presented while the previous one is still
        // dismissing, and the next anchor may be scrolled offscreen. Clear the current
        // mark, let anchor views prepare (via coachPreparingStep), then present once
        // the dismissal has settled.
        if let step, coachStep != nil {
            coachStep = nil
            coachPreparingStep = step
            coachTransitionTask = Task { @MainActor in
                try? await Task.sleep(for: OnboardingCoachStep.presentationSettleDelay)
                guard !Task.isCancelled else { return }
                coachPreparingStep = nil
                withAnimation(.easeOut(duration: 0.2)) {
                    coachStep = step
                }
            }
            return
        }
        coachPreparingStep = nil
        #endif
        withAnimation(.easeOut(duration: 0.2)) {
            coachStep = step
        }
    }

    private func ensureRowSelected() {
        guard selectedRowId == nil, let first = rows.first else { return }
        selectRow(first.id)
    }
}
