import SwiftUI
import Translation

enum LocaleMenuRequest {
    case manageLocales
    case editTranslations
    case autoTranslateMissing
    case reTranslateAll
    case revertToBase
}

struct LocaleToolbarMenu: View {
    @Bindable var state: AppState
    @State private var isManagingLocales = false
    @State private var isTranslationOverview = false
    @State private var quickTranslationConfig: TranslationSession.Configuration?
    @State private var quickTranslateOnlyUntranslated = true
    @State private var isQuickTranslating = false
    @State private var showReplaceAllConfirmation = false
    @State private var showResetToBaseConfirmation = false
    @State private var showLanguageDownloadAlert = false

    var body: some View {
        Menu {
            ForEach(state.localeState.locales) { locale in
                Button {
                    state.setActiveLocale(locale.code)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(locale.flagLabel)
                            Text(locale.code.uppercased())
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if locale.code == state.localeState.baseLocaleCode {
                            Text("Base")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        if locale.code == state.localeState.activeLocaleCode {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            Divider()
            let progress = state.translationProgress()
            if !state.localeState.isBaseLocale {
                Button("Auto-Translate Missing Text") {
                    startQuickTranslation(onlyUntranslated: true)
                }
                .disabled(
                    isQuickTranslating ||
                    progress.total == 0 ||
                    progress.translated >= progress.total
                )

                Button("Re-Translate All Text...") {
                    showReplaceAllConfirmation = true
                }
                .disabled(isQuickTranslating || progress.total == 0)

                Button("Revert to Base Language...", role: .destructive) {
                    showResetToBaseConfirmation = true
                }
                .disabled(isQuickTranslating || !state.localeState.activeLocaleHasOverrides)

                Divider()
            }
            if state.localeState.locales.count > 1 {
                Button("Edit Translation Table...") {
                    isTranslationOverview = true
                }
                .disabled(progress.total == 0)
            }
            Button("Manage Locales...") {
                isManagingLocales = true
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(state.localeState.activeLocaleCode.uppercased())
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.primary)

                        if state.localeState.locales.count > 1 {
                            Text("\(state.localeState.locales.count)")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.12), in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                    }

                    let status = activeLocaleStatus
                    Text(status.text)
                        .font(.system(size: 9))
                        .foregroundStyle(status.color)
                        .lineLimit(1)
                }
            }
        }
        .menuStyle(.button)
        .help(localeHelpText)
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
            Text("This removes all translated text and locale-specific image overrides for the current language, so the project uses the base language text and images again.")
        }
        .translationTask(quickTranslationConfig) { session in
            isQuickTranslating = true
            defer { isQuickTranslating = false }
            let targetLocaleCode = state.localeState.activeLocaleCode
            let success = await translateShapes(
                session: session,
                state: state,
                targetLocaleCode: targetLocaleCode,
                onlyUntranslated: quickTranslateOnlyUntranslated
            )
            if !success {
                showLanguageDownloadAlert = true
            }
        }
        .translationLanguageDownloadAlert(isPresented: $showLanguageDownloadAlert)
        .onChange(of: state.pendingLocaleMenuRequest) { _, newValue in
            guard let request = newValue else { return }
            state.pendingLocaleMenuRequest = nil
            switch request {
            case .manageLocales: isManagingLocales = true
            case .editTranslations: isTranslationOverview = true
            case .autoTranslateMissing: startQuickTranslation(onlyUntranslated: true)
            case .reTranslateAll: showReplaceAllConfirmation = true
            case .revertToBase: showResetToBaseConfirmation = true
            }
        }
    }

    private var localeHelpText: LocalizedStringKey {
        if state.localeState.locales.count > 1 {
            return "Language (\u{2318}[ / \u{2318}], \u{2325}\u{2318}0 to switch to the base language)"
        }
        return "Language"
    }

    private var activeLocaleStatus: (text: String, color: Color) {
        if state.localeState.isBaseLocale {
            let text = state.localeState.locales.count > 1 ? "Base language" : state.localeState.activeLocaleLabel
            return (text, .secondary)
        }

        let progress = state.translationProgress()
        if progress.total == 0 {
            return ("Locale-specific editing", .secondary)
        }

        let missingCount = max(progress.total - progress.translated, 0)
        if missingCount > 0 {
            return ("\(missingCount) untranslated", .orange)
        }
        return ("Translations complete", .secondary)
    }

    private func startQuickTranslation(onlyUntranslated: Bool) {
        quickTranslateOnlyUntranslated = onlyUntranslated
        quickTranslationConfig.refresh(
            source: state.localeState.baseLocaleCode,
            target: state.localeState.activeLocaleCode
        )
    }
}

// MARK: - Non-base Locale Banner

struct LocaleBanner: View {
    @Bindable var state: AppState
    @State private var translationConfig: TranslationSession.Configuration?
    @State private var isTranslating = false
    @State private var translateOnlyUntranslated = true
    @State private var pendingShapeFilter: Set<UUID>?
    @State private var showReplaceAllConfirmation = false
    @State private var showResetToBaseConfirmation = false
    @State private var isTranslationOverviewPresented = false
    @State private var showLanguageDownloadAlert = false
    @State private var showLocaleHelp = false

    private var selectedTextShapeIds: Set<UUID> {
        guard let rowIndex = state.selectedRowIndex else { return [] }
        let selected = state.selectedShapeIds
        let ids = state.rows[rowIndex].shapes
            .filter { selected.contains($0.id) && $0.type == .text && !($0.text ?? "").isEmpty }
            .map(\.id)
        return Set(ids)
    }

    var body: some View {
        let localeState = state.localeState
        if !localeState.isBaseLocale {
            let label = localeState.activeLocaleLabel
            let progress = state.translationProgress()
            let missingCount = max(progress.total - progress.translated, 0)
            VStack(spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "globe")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.localeWarning)

                    HStack(spacing: 6) {
                        Text("Editing \(label)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.localeWarning)
                        if progress.total > 0 {
                            Text("\(progress.translated) of \(progress.total)")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.localeWarning.opacity(0.12), in: Capsule())
                                .foregroundStyle(Color.localeWarning)
                        }
                        Button {
                            showLocaleHelp.toggle()
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.localeWarning.opacity(0.6))
                        }
                        .buttonStyle(.borderless)
                        .focusable(false)
                        .popover(isPresented: $showLocaleHelp, arrowEdge: .bottom) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Locale Editing")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Changes here affect only \(label). The base language text is shared across all locales — edits to other locales are stored as overrides.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 4) {
                                    Label("Edit translations manually or use Auto-Translate", systemImage: "character.book.closed")
                                    Label("Leave a field empty to fall back to base language", systemImage: "arrow.uturn.backward")
                                    Label("Use Edit Translations for a side-by-side view", systemImage: "tablecells")
                                }
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .frame(width: 300, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer(minLength: 8)

                    let selectedIds = selectedTextShapeIds
                    if !selectedIds.isEmpty {
                        Button {
                            startTranslation(onlyUntranslated: false, shapeIds: selectedIds)
                        } label: {
                            Label("Translate Selected", systemImage: "globe")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .font(.system(size: 11, weight: .medium))
                        .disabled(isTranslating)
                        .help("Translate selected text layers into \(label)")
                    }

                    if progress.total > 0 {
                        Button("Edit Translations") {
                            isTranslationOverviewPresented = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .font(.system(size: 11, weight: .medium))

                        Menu {
                            Button("Auto-Translate Missing Text") {
                                startTranslation(onlyUntranslated: true)
                            }
                            .disabled(isTranslating || missingCount == 0)

                            Button("Replace All Text…") {
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
                        .controlSize(.small)
                        .font(.system(size: 11, weight: .medium))
                        .disabled(isTranslating)
                    }

                    Button("Switch to Base") {
                        state.setActiveLocale(localeState.baseLocaleCode)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .font(.system(size: 11, weight: .medium))
                    .help("Switch to the base language (\u{2325}\u{2318}0)")

                    Button("Revert to Base", role: .destructive) {
                        showResetToBaseConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .font(.system(size: 11, weight: .medium))
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
                Text("This removes all translated text and locale-specific image overrides for \(label), so the project uses the base language text and images again.")
            }
            .translationTask(translationConfig) { session in
                isTranslating = true
                defer { isTranslating = false }
                let targetLocaleCode = state.localeState.activeLocaleCode
                let filterIds = pendingShapeFilter
                pendingShapeFilter = nil
                let success = await translateShapes(
                    session: session,
                    state: state,
                    targetLocaleCode: targetLocaleCode,
                    onlyUntranslated: translateOnlyUntranslated,
                    shapeFilter: filterIds.map { ids in { ids.contains($0) } }
                )
                if !success {
                    showLanguageDownloadAlert = true
                }
            }
            .translationLanguageDownloadAlert(isPresented: $showLanguageDownloadAlert)
            .onChange(of: state.pendingTranslateShapeId) { _, newValue in
                guard let shapeId = newValue else { return }
                state.pendingTranslateShapeId = nil
                startTranslation(onlyUntranslated: false, shapeIds: [shapeId])
            }
        }
    }

    private func startTranslation(onlyUntranslated: Bool, shapeIds: Set<UUID>? = nil) {
        translateOnlyUntranslated = onlyUntranslated
        pendingShapeFilter = shapeIds
        translationConfig.refresh(
            source: state.localeState.baseLocaleCode,
            target: state.localeState.activeLocaleCode
        )
    }
}
