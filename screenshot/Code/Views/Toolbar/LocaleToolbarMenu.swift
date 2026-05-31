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
    @State private var quickTranslateOnlyUntranslated = true
    @State private var isQuickTranslating = false
    @State private var showReplaceAllConfirmation = false
    @State private var showResetToBaseConfirmation = false
    @State private var showLanguageDownloadAlert = false
    @State private var fanOutConfig: TranslationSession.Configuration?
    @State private var fanOutPendingTargets: [String] = []
    @State private var fanOutShapeIds: Set<UUID> = []
    @State private var showFanOutLanguageDownloadAlert = false

    var body: some View {
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
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
        .coachPopover(step: .locale, state: state, arrowEdge: .top)
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
        .translationTask(fanOutConfig) { session in
            guard let target = fanOutPendingTargets.first else { return }
            let ids = fanOutShapeIds
            let success = await translateShapes(
                session: session,
                state: state,
                targetLocaleCode: target,
                onlyUntranslated: false,
                shapeFilter: { ids.contains($0) }
            )
            if !success {
                fanOutPendingTargets.removeAll()
                fanOutShapeIds.removeAll()
                state.isFanOutTranslating = false
                showFanOutLanguageDownloadAlert = true
                return
            }
            fanOutPendingTargets.removeFirst()
            if let next = fanOutPendingTargets.first {
                fanOutConfig.refresh(source: state.localeState.baseLocaleCode, target: next)
            } else {
                fanOutShapeIds.removeAll()
                state.isFanOutTranslating = false
            }
        }
        .translationLanguageDownloadAlert(isPresented: $showFanOutLanguageDownloadAlert)
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
        .onChange(of: state.pendingFanOutTranslateShapeIds) { _, newValue in
            guard let ids = newValue, !ids.isEmpty else { return }
            state.pendingFanOutTranslateShapeIds = nil
            guard !state.isFanOutTranslating else { return }
            let base = state.localeState.baseLocaleCode
            let targets = state.localeState.locales.map(\.code).filter { $0 != base }
            guard !targets.isEmpty else { return }
            fanOutShapeIds = ids
            fanOutPendingTargets = targets
            state.isFanOutTranslating = true
            fanOutConfig.refresh(source: base, target: targets[0])
        }
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
                            .font(.system(size: 11, weight: .medium))
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
        quickTranslateOnlyUntranslated = onlyUntranslated
        quickTranslationConfig.refresh(
            source: state.localeState.baseLocaleCode,
            target: state.localeState.activeLocaleCode
        )
    }
}

// MARK: - Locale Flag Chip

private struct LocaleFlagChip: View {
    let locale: LocaleDefinition
    let isActive: Bool
    let helpText: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if !locale.flag.isEmpty {
                    Text(locale.flag)
                        .font(.system(size: 13))
                }
                Text(locale.code.uppercased())
                    .font(.system(size: UIMetrics.FontSize.inlineLabel, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(isActive ? Color.white : Color.primary)
            .padding(.horizontal, 7)
            .frame(height: UIMetrics.IconButton.frameSize)
            .background(
                RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.chip, style: .continuous)
                    .fill(isActive
                          ? Color.accentColor
                          : Color.primary.opacity(UIMetrics.Opacity.sectionFill))
            )
            .overlay(
                RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.chip, style: .continuous)
                    .strokeBorder(
                        isActive
                          ? Color.accentColor
                          : Color.primary.opacity(UIMetrics.Opacity.hairlineOverlay),
                        lineWidth: isActive
                          ? UIMetrics.BorderWidth.emphasis
                          : UIMetrics.BorderWidth.hairline
                    )
            )
            .shadow(
                color: isActive ? Color.accentColor.opacity(0.35) : .clear,
                radius: isActive ? 4 : 0,
                x: 0,
                y: isActive ? 1 : 0
            )
        }
        .buttonStyle(.plain)
        .help(helpText)
    }
}

// MARK: - Flow Layout

private struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat = 4
    var verticalSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews: subviews, maxWidth: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let positions = arrange(subviews: subviews, maxWidth: bounds.width).positions
        for (index, point) in positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> (positions: [CGPoint], size: CGSize) {
        var positions: [CGPoint] = []
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var y: CGFloat = 0
        var maxRowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0 && rowWidth + horizontalSpacing + size.width > maxWidth {
                maxRowWidth = max(maxRowWidth, rowWidth)
                y += rowHeight + verticalSpacing
                rowWidth = 0
                rowHeight = 0
            }
            let x = rowWidth == 0 ? 0 : rowWidth + horizontalSpacing
            positions.append(CGPoint(x: x, y: y))
            rowWidth = x + size.width
            rowHeight = max(rowHeight, size.height)
        }
        maxRowWidth = max(maxRowWidth, rowWidth)
        return (positions, CGSize(width: maxRowWidth, height: y + rowHeight))
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
                                Text("Language Editing")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Changes here affect only \(label). The base language text is shared across all languages — edits to other languages are stored as overrides.")
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

                    let selectedIds = state.selectedTranslatableTextShapeIds
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
                        .controlSize(.small)
                        .font(.system(size: 11, weight: .medium))
                        .disabled(isTranslating)
                    }

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
                Text("This removes all translated text and language-specific image overrides for \(label), so the project uses the base language text and images again.")
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
