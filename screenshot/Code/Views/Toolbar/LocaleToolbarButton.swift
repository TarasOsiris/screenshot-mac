import SwiftUI

struct LocaleToolbarButton: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Bindable var state: AppState

    var body: some View {
        let localeState = state.localeState
        let activeCode = localeState.activeLocaleCode
        let baseCode = localeState.baseLocaleCode
        let progress = state.translationProgress()
        Menu {
            ForEach(localeState.locales) { locale in
                Button {
                    state.setActiveLocale(locale.code)
                } label: {
                    let title = locale.code == baseCode
                        ? "\(locale.flagLabel) (Base)"
                        : locale.flagLabel
                    if locale.code == activeCode {
                        Label(title, systemImage: "checkmark")
                    } else {
                        Text(title)
                    }
                }
            }

            if localeState.isBaseLocale, localeState.nonBaseLocaleCount > 0 {
                let ids = state.selectedTranslatableTextShapeIds
                if !ids.isEmpty {
                    Divider()
                    Button("Translate Selected to All Languages", systemImage: "character.bubble") {
                        state.pendingFanOutTranslateShapeIds = ids
                    }
                    .disabled(state.isFanOutTranslating)
                }
            }

            if !localeState.isBaseLocale {
                Divider()
                Button("Auto-Translate Missing Text", systemImage: "character.bubble") {
                    state.pendingLocaleMenuRequest = .autoTranslateMissing
                }
                .disabled(progress.total == 0 || progress.translated >= progress.total)

                Button("Re-Translate All Text...", systemImage: "arrow.triangle.2.circlepath") {
                    state.pendingLocaleMenuRequest = .reTranslateAll
                }
                .disabled(progress.total == 0)

                Button("Revert to Base Language...", systemImage: "arrow.uturn.backward", role: .destructive) {
                    state.pendingLocaleMenuRequest = .revertToBase
                }
                .disabled(!localeState.activeLocaleHasOverrides)
            }

            Divider()
            if localeState.locales.count > 1 {
                Button("Edit Translation Table...", systemImage: "tablecells") {
                    state.pendingLocaleMenuRequest = .editTranslations
                }
                .disabled(progress.total == 0)
            }
            Button("Manage Languages...", systemImage: "globe") {
                state.pendingLocaleMenuRequest = .manageLocales
            }
        } label: {
            localeLabel
        }
        .help("Language options")
        .coachPopoverAnchor(step: .locale, state: state)
    }

    @ViewBuilder
    private var localeLabel: some View {
        if state.localeState.isBaseLocale {
            Image(systemName: "globe")
                .accessibilityLabel("Localization")
        } else {
            let flag = state.localeState.locales.first { $0.code == state.localeState.activeLocaleCode }?.flag ?? ""
            HStack(spacing: 4) {
                if horizontalSizeClass != .compact || flag.isEmpty {
                    Image(systemName: "globe")
                }
                if !flag.isEmpty {
                    Text(flag)
                }
            }
            .foregroundStyle(Color.localeWarning)
        }
    }
}
