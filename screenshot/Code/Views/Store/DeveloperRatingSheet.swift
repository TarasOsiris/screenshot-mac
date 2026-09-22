import SwiftUI

/// A one-time personal ask, shown once `DeveloperRatingPromptPolicy` fires — a small card from the
/// developer directly, rather than the system `SKStoreReviewController` sheet `ReviewPromptPolicy`
/// triggers separately.
struct DeveloperRatingSheet: View {
    let onMaybeLater: () -> Void
    let onRate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                Image("DeveloperAvatar")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())
                    .overlay {
                        Circle().strokeBorder(
                            .separator.opacity(UIMetrics.Opacity.sectionBorder),
                            lineWidth: UIMetrics.BorderWidth.hairline
                        )
                    }
                    .accessibilityHidden(true)

                Text("A quick favor?")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("""
                    I built Screenshot Bro and use it myself every day to ship App Store \
                    screenshots for my other apps. If it's helping you too, a quick rating on the \
                    App Store keeps this app alive.
                    """)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // A name is not copy — the translation scripts would otherwise machine-translate
                // the signature on the developer's own note.
                Text(verbatim: "— Taras Leskiv")
                    .font(.system(size: 15, weight: .medium, design: .serif))
                    .italic()
                    .foregroundStyle(Color.accentColor)
            }

            Spacer(minLength: 0)

            actions
        }
        .padding(UIMetrics.Spacing.modal)
        #if os(macOS)
        .frame(width: 440, height: 270)
        .background(Color.platformWindowBackground)
        #else
        // iPhone is a shipping size here, so the card can't carry a desktop's fixed width — it
        // caps its column and lets the sheet size itself to that content.
        .frame(maxWidth: 420)
        .presentationSizing(.fitted)
        #endif
    }

    /// Trailing-aligned row on macOS, the platform's dialog convention; full-width stack on iOS,
    /// where the two titles side by side don't survive an iPhone's width.
    @ViewBuilder
    private var actions: some View {
        let maybeLater = Button("Maybe Later", action: onMaybeLater)
        let rate = Button("Rate Screenshot Bro", action: onRate)
            .keyboardShortcut(.defaultAction)

        #if os(macOS)
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            maybeLater.buttonStyle(.bordered)
            rate.buttonStyle(.borderedProminent)
        }
        .controlSize(.large)
        #else
        VStack(spacing: 10) {
            rate
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            maybeLater
                .buttonStyle(.borderless)
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        #endif
    }
}

#Preview {
    DeveloperRatingSheet(onMaybeLater: {}, onRate: {})
}
