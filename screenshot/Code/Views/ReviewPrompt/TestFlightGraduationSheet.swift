import SwiftUI

/// Thanks TestFlight testers and sends them to the App Store build; see `TestFlightGraduationPolicy`.
struct TestFlightGraduationSheet: View {
    let onNotNow: () -> Void
    let onOpenAppStore: () -> Void

    var body: some View {
        DeveloperNoteCard(
            title: "Thank you for testing!",
            message: """
                Screenshot Bro is now on the App Store, and your feedback helped get it \
                there. This beta will stop receiving updates soon, so please install the App \
                Store version — it replaces this one, and your projects stay right where they are.
                """,
            secondaryTitle: "Not Now",
            primaryTitle: "Open App Store",
            onSecondary: onNotNow,
            onPrimary: onOpenAppStore,
            macHeight: 280
        )
    }
}

/// Checks once per launch and presents `TestFlightGraduationSheet` when the policy says so.
private struct TestFlightGraduationPrompt: ViewModifier {
    /// Held back while another full-surface modal owns the window; SwiftUI shows one at a time.
    let isSuppressed: Bool

    @Environment(\.openURL) private var openURL
    @State private var isPending = false
    @State private var didOpenAppStore = false

    func body(content: Content) -> some View {
        content
            .task {
                isPending = await TestFlightGraduationPolicy.shouldPromptThisLaunch.value
            }
            .sheet(isPresented: Binding(get: { isPending && !isSuppressed },
                                        set: { if !$0 { isPending = false } }),
                   onDismiss: reportOutcome) {
                TestFlightGraduationSheet(
                    onNotNow: { isPending = false },
                    onOpenAppStore: {
                        didOpenAppStore = true
                        isPending = false
                        openURL(AppLinks.appStorePage)
                    }
                )
                .onAppear {
                    TestFlightGraduationPolicy().markShown()
                    AnalyticsService.capture(.testFlightGraduationShown)
                }
            }
    }

    /// From `onDismiss` so Esc, a click outside and the iPad swipe-down are counted too.
    private func reportOutcome() {
        AnalyticsService.capture(didOpenAppStore ? .testFlightGraduationAccepted : .testFlightGraduationDismissed)
        didOpenAppStore = false
    }
}

extension View {
    func testFlightGraduationPrompt(isSuppressed: Bool = false) -> some View {
        modifier(TestFlightGraduationPrompt(isSuppressed: isSuppressed))
    }
}

#Preview {
    TestFlightGraduationSheet(onNotNow: {}, onOpenAppStore: {})
}
