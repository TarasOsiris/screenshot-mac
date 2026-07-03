import SwiftUI
import Translation

enum LocaleMenuRequest {
    case manageLocales
    case editTranslations
    case autoTranslateMissing
    case reTranslateAll
    case revertToBase
}

struct LocaleBar: View {
    @Bindable var state: AppState
    @State private var isManagingLocales = false
    @State private var isTranslationOverview = false
    @State private var quickTranslationConfig: TranslationSession.Configuration?
    @State private var quickTranslationTargetCode = ""
    @State private var quickTranslateOnlyUntranslated = true
    @State private var isQuickTranslating = false
    @State private var showReplaceAllConfirmation = false
    @State private var showResetToBaseConfirmation = false
    @State private var languageIssue: TranslationLanguageIssue?
    @State private var fanOutConfig: TranslationSession.Configuration?
    @State private var fanOutPendingTargets: [String] = []
    @State private var fanOutShapeIds: Set<UUID> = []

    var body: some View {
        // On iPad the visible chip strip is replaced by the globe `LocaleToolbarButton`, but
        // LocaleBar stays mounted (zero-height) so its sheets / dialogs / translationTask /
        // onChange machinery keeps servicing the menu's state-driven requests.
        chipStrip
            .sheet(isPresented: $isManagingLocales) {
                ManageLocalesSheet(state: state)
            }
            .sheet(isPresented: $isTranslationOverview) {
                TranslationOverviewSheet(state: state)
            }
            .confirmationDialog(
                "Replace all \(state.localeState.activeLocaleLabel) text with new translations?",
                isPresented: $showReplaceAllConfirmation
            ) {
                Button("Replace All Text", role: .destructive) {
                    startQuickTranslation(onlyUntranslated: false)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This applies translation from the base language to every text layer in \(state.localeState.activeLocaleLabel) and replaces the current translated text.")
            }
            .confirmationDialog(
                "Reset all \(state.localeState.activeLocaleLabel) text and image overrides?",
                isPresented: $showResetToBaseConfirmation
            ) {
                Button("Revert to Base", role: .destructive) {
                    state.resetActiveLocaleToBase()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes all translated text and language-specific image overrides for the current language, so the project uses the base language text and images again.")
            }
            .translationTask(quickTranslationConfig) { session in
                await runQuickTranslation(session)
            }
            .translationTask(fanOutConfig) { session in
                await runFanOutTranslation(session)
            }
            .translationLanguageIssueAlert(item: $languageIssue)
            .onChange(of: state.pendingLocaleMenuRequest) { _, newValue in
                handleLocaleMenuRequest(newValue)
            }
            .onChange(of: state.pendingFanOutTranslateShapeIds) { _, newValue in
                startFanOutTranslation(shapeIds: newValue)
            }
    }

    @ViewBuilder
    private var chipStrip: some View {
        #if os(macOS)
        let baseCode = state.localeState.baseLocaleCode
        let activeCode = state.localeState.activeLocaleCode
        FlowLayout(horizontalSpacing: 4, verticalSpacing: 4) {
            localeActionsMenu

            if state.isFanOutTranslating {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.small)
                    Text("Translating…")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 6)
                .frame(height: UIMetrics.IconButton.frameSize)
            }

            ForEach(state.localeState.locales) { locale in
                LocaleFlagChip(
                    locale: locale,
                    isActive: locale.code == activeCode,
                    helpText: locale.code == baseCode ? "\(locale.label) — Base language" : locale.label,
                    action: { state.setActiveLocale(locale.code) }
                )
            }

            addLanguageButton

            fanOutTranslateButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.platformWindowBackground)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .coachPopover(step: .locale, state: state, arrowEdge: .top)
        #else
        // iPad: invisible presenter; the globe toolbar button drives all locale actions.
        Color.clear.frame(height: 0)
        #endif
    }

    private var addLanguageButton: some View {
        ActionButton(
            icon: "plus.circle",
            tooltip: "Add Language…",
            iconSize: 13,
            frameSize: UIMetrics.IconButton.frameSize
        ) {
            isManagingLocales = true
        }
    }

    @ViewBuilder
    private var fanOutTranslateButton: some View {
        let count = state.localeState.nonBaseLocaleCount
        if state.localeState.isBaseLocale, count > 0 {
            let ids = state.selectedTranslatableTextShapeIds
            if !ids.isEmpty {
                Button {
                    state.pendingFanOutTranslateShapeIds = ids
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "character.bubble")
                            .font(.system(size: UIMetrics.FontSize.body, weight: .medium))
                        Text("Translate Selected to All Languages")
                            .font(.system(size: UIMetrics.FontSize.body, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .frame(height: UIMetrics.IconButton.frameSize)
                    .background(
                        RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.chip, style: .continuous)
                            .fill(Color.accentColor)
                    )
                }
                .buttonStyle(.plain)
                .disabled(state.isFanOutTranslating)
                .opacity(state.isFanOutTranslating ? UIMetrics.Opacity.disabled : 1)
                .help("Translate \(ids.count == 1 ? "this text" : "the \(ids.count) selected texts") into all \(count) other language\(count == 1 ? "" : "s")")
            }
        }
    }

    @ViewBuilder
    private var localeActionsMenu: some View {
        Menu {
            let progress = state.translationProgress()
            if !state.localeState.isBaseLocale {
                Button("Auto-Translate Missing Text", systemImage: "character.bubble") {
                    startQuickTranslation(onlyUntranslated: true)
                }
                .disabled(
                    isQuickTranslating ||
                    progress.total == 0 ||
                    progress.translated >= progress.total
                )

                Button("Re-Translate All Text...", systemImage: "arrow.triangle.2.circlepath") {
                    showReplaceAllConfirmation = true
                }
                .disabled(isQuickTranslating || progress.total == 0)

                Button("Revert to Base Language...", systemImage: "arrow.uturn.backward", role: .destructive) {
                    showResetToBaseConfirmation = true
                }
                .disabled(isQuickTranslating || !state.localeState.activeLocaleHasOverrides)

                Divider()
            }
            if state.localeState.locales.count > 1 {
                Button("Edit Translation Table...", systemImage: "tablecells") {
                    isTranslationOverview = true
                }
                .disabled(progress.total == 0)
            }
            Button("Manage Languages...", systemImage: "globe") {
                isManagingLocales = true
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: UIMetrics.IconButton.frameSize, height: UIMetrics.IconButton.frameSize)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .help("Language options")
    }

    private func startQuickTranslation(onlyUntranslated: Bool) {
        // Pin the target locale at start so a mid-run locale switch can't redirect output.
        // Source is always the base locale.
        quickTranslationTargetCode = state.localeState.activeLocaleCode
        quickTranslateOnlyUntranslated = onlyUntranslated
        quickTranslationConfig.refresh(
            source: state.localeState.baseLocaleCode,
            target: quickTranslationTargetCode
        )
    }

    private func runQuickTranslation(_ session: TranslationSession) async {
        isQuickTranslating = true
        defer { isQuickTranslating = false }
        let targetCode = quickTranslationTargetCode
        guard !targetCode.isEmpty else { return }
        let result = await translateShapes(
            session: session,
            state: state,
            targetLocaleCode: targetCode,
            onlyUntranslated: quickTranslateOnlyUntranslated
        )
        languageIssue = TranslationLanguageIssue(result, language: state.localeState.languageLabel(for: targetCode))
    }

    private func runFanOutTranslation(_ session: TranslationSession) async {
        guard let target = fanOutPendingTargets.first else { return }
        let ids = fanOutShapeIds
        let result = await translateShapes(
            session: session,
            state: state,
            targetLocaleCode: target,
            onlyUntranslated: false,
            shapeFilter: { ids.contains($0) }
        )

        guard result == .completed else {
            finishFanOutTranslation()
            languageIssue = TranslationLanguageIssue(result, language: state.localeState.languageLabel(for: target))
            return
        }

        fanOutPendingTargets.removeFirst()
        if let next = fanOutPendingTargets.first {
            fanOutConfig.refresh(source: state.localeState.baseLocaleCode, target: next)
        } else {
            finishFanOutTranslation()
        }
    }

    private func finishFanOutTranslation() {
        fanOutPendingTargets.removeAll()
        fanOutShapeIds.removeAll()
        state.isFanOutTranslating = false
    }

    private func handleLocaleMenuRequest(_ request: LocaleMenuRequest?) {
        guard let request else { return }
        state.pendingLocaleMenuRequest = nil
        switch request {
        case .manageLocales: isManagingLocales = true
        case .editTranslations: isTranslationOverview = true
        case .autoTranslateMissing: startQuickTranslation(onlyUntranslated: true)
        case .reTranslateAll: showReplaceAllConfirmation = true
        case .revertToBase: showResetToBaseConfirmation = true
        }
    }

    private func startFanOutTranslation(shapeIds: Set<UUID>?) {
        guard let shapeIds, !shapeIds.isEmpty else { return }
        state.pendingFanOutTranslateShapeIds = nil
        guard !state.isFanOutTranslating else { return }
        let base = state.localeState.baseLocaleCode
        let targets = state.localeState.locales.map(\.code).filter { $0 != base }
        guard !targets.isEmpty else { return }
        fanOutShapeIds = shapeIds
        fanOutPendingTargets = targets
        state.isFanOutTranslating = true
        fanOutConfig.refresh(source: base, target: targets[0])
    }
}
