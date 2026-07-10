import SwiftUI
@preconcurrency import Translation

struct LocaleBanner: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Bindable var state: AppState
    @State private var translationConfig: TranslationSession.Configuration?
    @State private var translationTargetCode = ""
    @State private var isTranslating = false
    @State private var translateOnlyUntranslated = true
    @State private var pendingShapeFilter: Set<UUID>?
    @State private var showReplaceAllConfirmation = false
    @State private var showResetToBaseConfirmation = false
    @State private var isTranslationOverviewPresented = false
    @State private var languageIssue: TranslationLanguageIssue?
    @State private var showLocaleHelp = false

    var body: some View {
        let localeState = state.localeState
        if !localeState.isBaseLocale {
            let label = localeState.activeLocaleLabel
            let progress = state.translationProgress()
            let missingCount = max(progress.total - progress.translated, 0)
            VStack(spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "globe")
                        .font(.system(size: UIMetrics.FontSize.menuRow, weight: .semibold))
                        .foregroundStyle(Color.localeWarning)

                    HStack(spacing: 6) {
                        Text(label)
                            .font(.system(size: UIMetrics.FontSize.menuRow, weight: .semibold))
                            .foregroundStyle(Color.localeWarning)
                        if progress.total > 0 {
                            Text("\(progress.translated) of \(progress.total)")
                                .font(.system(size: UIMetrics.FontSize.numericBadge, weight: .medium, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.localeWarning.opacity(0.12), in: Capsule())
                                .foregroundStyle(Color.localeWarning)
                        }
                        Button {
                            showLocaleHelp.toggle()
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: UIMetrics.FontSize.menuRow))
                                .foregroundStyle(Color.localeWarning.opacity(0.6))
                        }
                        .buttonStyle(.borderless)
                        .focusable(false)
                        .popover(isPresented: $showLocaleHelp, arrowEdge: .bottom) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Language Editing")
                                    .font(.system(size: UIMetrics.FontSize.menuRow, weight: .semibold))
                                Text("Changes here affect only \(label). The base language text is shared across all languages — edits to other languages are stored as overrides.")
                                    .font(.system(size: UIMetrics.FontSize.body))
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 4) {
                                    Label("Edit translations manually or use Auto-Translate", systemImage: "character.book.closed")
                                    Label("Leave a field empty to fall back to base language", systemImage: "arrow.uturn.backward")
                                    Label("Use Edit Translations for a side-by-side view", systemImage: "tablecells")
                                }
                                .font(.system(size: UIMetrics.FontSize.body))
                                .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .frame(width: 300, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            #if os(macOS)
                            .presentationCompactAdaptation(.popover)
                            #else
                            .presentationCompactAdaptation(.sheet)
                            .presentationDetents([.medium])
                            #endif
                        }
                    }

                    Spacer(minLength: 8)

                    if horizontalSizeClass == .compact {
                        compactActionsMenu(label: label, progress: progress, missingCount: missingCount)
                    } else {
                        expandedActions(label: label, progress: progress, missingCount: missingCount)
                    }
                }

            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Color.localeWarning.opacity(0.15))
            .sheet(isPresented: $isTranslationOverviewPresented) {
                TranslationOverviewSheet(state: state)
            }
            .confirmationDialog(
                "Replace all \(label) text with new translations?",
                isPresented: $showReplaceAllConfirmation
            ) {
                Button("Replace All Text", role: .destructive) {
                    startTranslation(onlyUntranslated: false)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This applies translation from the base language to every text layer in \(label) and replaces the current translated text.")
            }
            .confirmationDialog(
                "Reset all \(label) text and image overrides?",
                isPresented: $showResetToBaseConfirmation
            ) {
                Button("Revert to Base", role: .destructive) {
                    state.resetActiveLocaleToBase()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes all translated text and language-specific image overrides for \(label), so the project uses the base language text and images again.")
            }
            .translationTask(translationConfig) { session in
                await runBannerTranslation(session)
            }
            .translationLanguageIssueAlert(item: $languageIssue)
            .onChange(of: state.pendingTranslateShapeId) { _, newValue in
                handlePendingTranslateShapeId(newValue)
            }
        }
    }

    @ViewBuilder
    private func expandedActions(label: String, progress: (translated: Int, total: Int), missingCount: Int) -> some View {
        let selectedIds = state.selectedTranslatableTextShapeIds
        if !selectedIds.isEmpty {
            Button {
                startTranslation(onlyUntranslated: false, shapeIds: selectedIds)
            } label: {
                Label("Translate Selected", systemImage: "globe")
            }
            .buttonStyle(.bordered)
            .compactControlSize()
            .font(.system(size: UIMetrics.FontSize.body, weight: .medium))
            .disabled(isTranslating)
            .help("Translate selected text layers into \(label)")
        }

        if progress.total > 0 {
            Button("Edit Translations") {
                isTranslationOverviewPresented = true
            }
            .buttonStyle(.bordered)
            .compactControlSize()
            .font(.system(size: UIMetrics.FontSize.body, weight: .medium))

            Menu {
                Button("Auto-Translate Missing Text", systemImage: "character.bubble") {
                    startTranslation(onlyUntranslated: true)
                }
                .disabled(isTranslating || missingCount == 0)

                Button("Replace All Text…", systemImage: "arrow.triangle.2.circlepath") {
                    showReplaceAllConfirmation = true
                }
                .disabled(isTranslating)
            } label: {
                if isTranslating {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Translating text…")
                    }
                } else {
                    Label("Auto-Translate", systemImage: "globe")
                }
            }
            .buttonStyle(.bordered)
            .compactControlSize()
            .font(.system(size: UIMetrics.FontSize.body, weight: .medium))
            .disabled(isTranslating)
        }

        Button("Revert to Base", role: .destructive) {
            showResetToBaseConfirmation = true
        }
        .buttonStyle(.bordered)
        .compactControlSize()
        .font(.system(size: UIMetrics.FontSize.body, weight: .medium))
    }

    @ViewBuilder
    private func compactActionsMenu(label: String, progress: (translated: Int, total: Int), missingCount: Int) -> some View {
        let selectedIds = state.selectedTranslatableTextShapeIds
        Menu {
            if !selectedIds.isEmpty {
                Button("Translate Selected", systemImage: "globe") {
                    startTranslation(onlyUntranslated: false, shapeIds: selectedIds)
                }
                .disabled(isTranslating)
            }

            if progress.total > 0 {
                Button("Edit Translations", systemImage: "tablecells") {
                    isTranslationOverviewPresented = true
                }

                Button("Auto-Translate Missing Text", systemImage: "character.bubble") {
                    startTranslation(onlyUntranslated: true)
                }
                .disabled(isTranslating || missingCount == 0)

                Button("Replace All Text…", systemImage: "arrow.triangle.2.circlepath") {
                    showReplaceAllConfirmation = true
                }
                .disabled(isTranslating)
            }

            Divider()

            Button("Revert to Base", systemImage: "arrow.uturn.backward", role: .destructive) {
                showResetToBaseConfirmation = true
            }
        } label: {
            if isTranslating {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(Color.localeWarning)
            }
        }
        .buttonStyle(.bordered)
        .compactControlSize()
        .disabled(isTranslating)
    }

    private func startTranslation(onlyUntranslated: Bool, shapeIds: Set<UUID>? = nil) {
        // Pin the target locale at start; source is always the base locale.
        translationTargetCode = state.localeState.activeLocaleCode
        translateOnlyUntranslated = onlyUntranslated
        pendingShapeFilter = shapeIds
        translationConfig.refresh(
            source: state.localeState.baseLocaleCode,
            target: translationTargetCode
        )
    }

    private func runBannerTranslation(_ session: TranslationSession) async {
        isTranslating = true
        // Clear the config so a stale one can't re-fire when the banner reattaches its
        // .translationTask on locale switch — that would silently re-translate everything.
        defer {
            isTranslating = false
            translationConfig = nil
        }
        let filterIds = pendingShapeFilter
        pendingShapeFilter = nil
        let targetCode = translationTargetCode
        guard !targetCode.isEmpty else { return }
        let shapeFilter: (@Sendable (UUID) -> Bool)?
        if let filterIds {
            shapeFilter = { id in filterIds.contains(id) }
        } else {
            shapeFilter = nil
        }
        let result = await translateShapes(
            session: session,
            state: state,
            targetLocaleCode: targetCode,
            onlyUntranslated: translateOnlyUntranslated,
            shapeFilter: shapeFilter
        )
        languageIssue = TranslationLanguageIssue(result, language: state.localeState.languageLabel(for: targetCode))
    }

    private func handlePendingTranslateShapeId(_ shapeId: UUID?) {
        guard let shapeId else { return }
        state.pendingTranslateShapeId = nil
        startTranslation(onlyUntranslated: false, shapeIds: [shapeId])
    }
}
