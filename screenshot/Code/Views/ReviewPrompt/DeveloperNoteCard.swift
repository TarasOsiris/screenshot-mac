import SwiftUI

/// A short signed note from the developer with two actions; the shared body of the review-prompt sheets.
struct DeveloperNoteCard: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let secondaryTitle: LocalizedStringKey
    let primaryTitle: LocalizedStringKey
    let onSecondary: () -> Void
    let onPrimary: () -> Void
    /// Ignored on iOS, where the sheet sizes itself to the content.
    var macHeight: CGFloat = 270

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

                Text(title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(message)
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
        .frame(width: 440, height: macHeight)
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
        let secondary = Button(secondaryTitle, action: onSecondary)
        let primary = Button(primaryTitle, action: onPrimary)
            .keyboardShortcut(.defaultAction)

        #if os(macOS)
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            secondary.buttonStyle(.bordered)
            primary.buttonStyle(.borderedProminent)
        }
        .controlSize(.large)
        #else
        VStack(spacing: 10) {
            primary
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            secondary
                .buttonStyle(.borderless)
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        #endif
    }
}
