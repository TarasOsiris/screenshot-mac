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

// MARK: - Locale Toolbar Button (iPad)

/// iPad globe toolbar action that folds the whole language-toggle bar into one pull-down Menu.
/// Drives everything through AppState (the same channels `LocaleBar` and the macOS menu bar use),
/// so the mounted-but-hidden `LocaleBar` executes the actual sheets/dialogs/translations.
struct LocaleToolbarButton: View {
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
            // Surface that a translation is being edited: globe + active flag in the warning tint.
            HStack(spacing: 4) {
                Image(systemName: "globe")
                let flag = state.localeState.locales.first { $0.code == state.localeState.activeLocaleCode }?.flag ?? ""
                if !flag.isEmpty {
                    Text(flag)
                }
            }
            .foregroundStyle(Color.localeWarning)
        }
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

    /// Lower bound for the width used when *measuring* the layout. SwiftUI probes a
    /// custom Layout with tiny widths (0, a few points) to discover its minimum size.
    /// At those widths every chip wraps onto its own row, so the bar reports a height of
    /// dozens of rows — which SwiftUI then treats as the bar's minimum height and forces
    /// the entire window taller than the screen (pushing the toolbar/rows off-screen).
    /// Clamping the *measurement* width to a realistic minimum keeps the reported size
    /// bounded. Placement still uses the true width, so wrapping at the real width is
    /// unaffected as long as the window can't get narrower than this.
    private static let minMeasuredWidth: CGFloat = 460

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = max(proposal.width ?? .infinity, Self.minMeasuredWidth)
        return arrange(subviews: subviews, maxWidth: width).size
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
                        Text("Editing \(label)")
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
        defer { isTranslating = false }
        let filterIds = pendingShapeFilter
        pendingShapeFilter = nil
        let targetCode = translationTargetCode
        guard !targetCode.isEmpty else { return }
        let result = await translateShapes(
            session: session,
            state: state,
            targetLocaleCode: targetCode,
            onlyUntranslated: translateOnlyUntranslated,
            shapeFilter: filterIds.map { ids in { ids.contains($0) } }
        )
        languageIssue = TranslationLanguageIssue(result, language: state.localeState.languageLabel(for: targetCode))
    }

    private func handlePendingTranslateShapeId(_ shapeId: UUID?) {
        guard let shapeId else { return }
        state.pendingTranslateShapeId = nil
        startTranslation(onlyUntranslated: false, shapeIds: [shapeId])
    }
}
