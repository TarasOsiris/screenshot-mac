import SwiftUI

/// A one-time personal ask, shown once `DeveloperRatingPromptPolicy` fires — a small card from the
/// developer directly, rather than the system `SKStoreReviewController` sheet `ReviewPromptPolicy`
/// triggers separately.
struct DeveloperRatingSheet: View {
    let onMaybeLater: () -> Void
    let onRate: () -> Void

    var body: some View {
        DeveloperNoteCard(
            title: "A quick favor?",
            message: """
                I built Screenshot Bro and use it myself every day to ship App Store \
                screenshots for my other apps. If it's helping you too, a quick rating on the \
                App Store keeps this app alive.
                """,
            secondaryTitle: "Maybe Later",
            primaryTitle: "Rate Screenshot Bro",
            onSecondary: onMaybeLater,
            onPrimary: onRate
        )
    }
}

#Preview {
    DeveloperRatingSheet(onMaybeLater: {}, onRate: {})
}
