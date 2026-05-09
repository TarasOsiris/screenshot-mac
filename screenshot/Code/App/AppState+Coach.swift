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
        // The inspector and shapes steps anchor on row-scoped UI, which only
        // renders when a row is selected.
        if next == .inspector || next == .shapes {
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
        withAnimation(.easeOut(duration: 0.2)) {
            coachStep = step
        }
    }

    private func ensureRowSelected() {
        guard selectedRowId == nil, let first = rows.first else { return }
        selectRow(first.id)
    }
}
