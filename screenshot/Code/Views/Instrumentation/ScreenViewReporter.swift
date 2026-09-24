import SwiftUI

// The app's navigation signal for PostHog. A native app emits no `$pageview` — `$screen` is the
// equivalent — and `AnalyticsService.start()` keeps every swizzled autocapture off, so screens are
// reported here, by hand, from the presented view itself.
extension View {
    /// Reports a `$screen` view each time this view comes on screen.
    ///
    /// Attach to the **presented content**, not to the presenter.
    ///
    /// Pass `restoring:` when the screen is a **sheet or cover**, and only then. Those cover their
    /// presenter without removing it, so the host's `onAppear` never re-fires on dismiss — and
    /// since the SDK stamps the last screen name onto every later event, a dismissed sheet would
    /// otherwise keep mislabelling the editor's exports as its own. A pushed destination needs no
    /// `restoring:`: the source view really does disappear and re-appear, so it re-reports itself.
    ///
    /// The cost of `restoring:` is that the host is re-reported on dismiss — the same shape a
    /// browser back navigation produces. Count "installs that reached the editor" by unique users,
    /// not by event volume.
    func screenView(_ screen: AnalyticsService.Screen,
                    restoring host: AnalyticsService.Screen? = nil) -> some View {
        modifier(ScreenViewReporter(screen: screen, host: host))
    }
}

private struct ScreenViewReporter: ViewModifier {
    let screen: AnalyticsService.Screen
    let host: AnalyticsService.Screen?

    /// SwiftUI may run `onAppear` more than once for one view identity without an intervening
    /// `onDisappear` (window tab switches, some container re-layouts). Tracking on-screen state
    /// rather than "have I ever reported" suppresses exactly those, while still letting a real
    /// leave-and-return — a nav pop, a tab switch, a reopened window — count as a new view.
    @State private var isOnScreen = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard !isOnScreen else { return }
                isOnScreen = true
                AnalyticsService.screen(screen)
            }
            .onDisappear {
                guard isOnScreen else { return }
                isOnScreen = false
                guard let host else { return }
                AnalyticsService.screen(host)
            }
    }
}
