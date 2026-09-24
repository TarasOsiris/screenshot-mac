import SwiftUI

struct OnboardingView: View {
    var persistCompletion = true
    var onComplete: (() -> Void)?

    @AppStorage(OnboardingPersistence.completedKey) private var onboardingCompleted = false
    #if os(iOS)
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(PurchaseService.self) var store
    @State var pageIndex = 0
    @State var templatePreviews: [NSImage] = []
    /// Skip jumps *to* the Pro page rather than exiting, so by the time `complete()` runs
    /// `pageIndex` claims the user reached the end. Remember where they actually bailed.
    @State var skippedFromPage: Int?
    #endif

    var body: some View {
        #if os(iOS)
        iOSContent
        #else
        OnboardingMacContent(onGetStarted: complete)
            .onAppear(perform: reportStarted)
        #endif
    }

    /// `persistCompletion == false` is the debug re-run path — counting it would inflate the
    /// funnel with our own walkthroughs, same rule as the coach tour.
    func reportStarted() {
        guard persistCompletion else { return }
        AnalyticsService.capture(.onboardingStarted, [.source: "welcome"])
        #if os(iOS)
        AnalyticsService.capture(
            .onboardingStepViewed,
            [.source: "welcome", .step: pageAnalyticsName(pageIndex)]
        )
        #endif
    }

    func complete() {
        if persistCompletion {
            onboardingCompleted = true
            #if os(iOS)
            // `lastStep` is the last page they actually engaged with — for a skip that is where
            // they bailed, not `pro`, which Skip would otherwise report for everyone.
            AnalyticsService.captureOnboardingEnd(
                welcomeOutcome,
                source: "welcome",
                lastStep: pageAnalyticsName(skippedFromPage ?? pageIndex)
            )
            #else
            AnalyticsService.captureOnboardingEnd(.finished, source: "welcome", lastStep: nil)
            #endif
        }
        #if os(iOS)
        // A purchase made inside onboarding already showed its own success state, so drop any
        // celebration the store queued — otherwise it would surface on the next root paywall.
        store.cancelPendingCelebration()
        #endif
        onComplete?()
    }

    // MARK: - Data

    static let stepData: [StepInfo] = [
        StepInfo(
            analyticsName: "templates",
            title: "Pick a template",
            description: "Start from a ready-made layout or a blank project. Templates come pre-sized for each store.",
            icon: "square.grid.2x2",
            color: .blue
        ),
        StepInfo(
            analyticsName: "content",
            title: "Add your content",
            description: "Drop in screenshots, add text and shapes, pick a device frame. Drag to arrange.",
            icon: "plus.rectangle.on.rectangle",
            hint: "Drop images onto canvas",
            iosDescription: "Add screenshots from Photos or Files, then drop in text, shapes, and a device frame.",
            illustration: .addContent,
            color: .purple
        ),
        StepInfo(
            analyticsName: "style",
            title: "Style it",
            description: "Set backgrounds, colors, and gradients. Use the inspector on the right and properties bar at the bottom.",
            icon: "paintbrush",
            iosDescription: "Set backgrounds, colors, and gradients, and fine-tune every element to match your brand.",
            illustration: .style,
            color: .orange
        ),
        StepInfo(
            analyticsName: "export",
            title: "Export",
            description: "Export all screenshots at once as PNG or JPEG, ready to upload to App Store Connect or Google Play.",
            icon: "square.and.arrow.up",
            shortcutGlyph: "\u{2318}E",
            illustration: .export,
            color: .green
        ),
    ]
}

/// The iOS-only animated illustration a step shows in place of its static icon. Keyed off the
/// step's data rather than its array index so reordering steps can't mismatch the illustration.
enum StepIllustration {
    case addContent, style, export
}

struct StepInfo {
    // Stable per-step vocabulary for the `step`/`last_step` analytics properties — never the
    // localized title, which would put user-language text on the wire.
    let analyticsName: String
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    let icon: String
    var hint: LocalizedStringKey?
    var shortcutGlyph: String?
    // Used by the iPad/iOS flow when the desktop copy references mouse/keyboard or chrome
    // (drag-drop, the right inspector, ⌘E) that doesn't exist there.
    var iosDescription: LocalizedStringKey?
    var illustration: StepIllustration?
    let color: Color
}

#Preview {
    #if os(iOS)
    // iOS body reads PurchaseService from the environment — inject one so the preview doesn't trap.
    OnboardingView()
        .environment(PurchaseService())
    #else
    OnboardingView()
    #endif
}
