import SwiftUI
import Translation

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
                .disabled(isQuickTranslating || !activeLocaleHasOverrides)

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
    }

    private var localeHelpText: String {
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

    private var activeLocaleHasOverrides: Bool {
        guard !state.localeState.isBaseLocale else { return false }
        return !(state.localeState.overrides[state.localeState.activeLocaleCode]?.isEmpty ?? true)
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

// MARK: - Manage Locales Sheet

private struct ManageLocalesSheet: View {
    @Bindable var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var showPresets = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("Manage Locales")
                    .font(.headline)
                Text("The first language is the base. Drag to reorder.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 16)
            .padding(.bottom, 12)

            List {
                ForEach(state.localeState.locales) { locale in
                    let progress = state.translationProgress(for: locale.code)
                    let isBase = locale.code == state.localeState.baseLocaleCode
                    HStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Text(locale.flagLabel)
                            .font(.system(size: 13))
                        Text(locale.code.uppercased())
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if isBase {
                            Text("Base")
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.12), in: Capsule())
                                .foregroundStyle(Color.accentColor)
                        } else {
                            if progress.total > 0 {
                                let statusColor: Color = progress.translated >= progress.total ? .green : .orange
                                Text("\(progress.translated)/\(progress.total)")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(statusColor.opacity(0.12), in: Capsule())
                                    .foregroundStyle(statusColor)
                            }
                            Button(role: .destructive) {
                                state.removeLocale(locale.code)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.borderless)
                            .focusable(false)
                            .foregroundStyle(.red.opacity(0.8))
                            .help("Delete locale")
                        }
                    }
                }
                .onMove { source, destination in
                    state.moveLocale(from: source, to: destination)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            Divider()

            HStack {
                Button {
                    showPresets = true
                } label: {
                    Label("Add Language", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 380, height: 340)
        .sheet(isPresented: $showPresets) {
            LocalePresetsSheet(state: state, searchText: $searchText)
        }
    }
}

// MARK: - Locale Presets Picker

private struct LocalePresetsSheet: View {
    @Bindable var state: AppState
    @Binding var searchText: String
    @Environment(\.dismiss) private var dismiss

    private var availablePresets: [LocaleDefinition] {
        let existing = Set(state.localeState.locales.map(\.code))
        let filtered = LocalePresets.all.filter { !existing.contains($0.code) }
        if searchText.isEmpty { return filtered }
        let query = searchText.lowercased()
        return filtered.filter {
            $0.code.lowercased().contains(query) || $0.label.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Add Language")
                .font(.headline)
                .padding(.top, 16)
                .padding(.bottom, 8)

            TextField("Search languages...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            List {
                ForEach(availablePresets) { locale in
                    HStack {
                        Text(locale.code)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 36, alignment: .leading)
                        Text(locale.flagLabel)
                        Spacer()
                        Button("Add") {
                            state.addLocale(locale)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Color.accentColor)
                    }
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(width: 340, height: 400)
    }
}

// MARK: - Translation Overview

private struct TranslationOverviewSheet: View {
    @Bindable var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var cellTranslationConfig: TranslationSession.Configuration?
    @State private var pendingCellTranslation: PendingCellTranslation?
    private let baseColumnWidth: CGFloat = 320
    private let translationColumnWidth: CGFloat = 260
    private let columnPadding: CGFloat = 12

    var body: some View {
        let items = state.textShapesForTranslationMatrix()
        let baseLocale = state.localeState.locales.first
        let translationLocales = Array(state.localeState.locales.dropFirst())

        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Edit Translations")
                    .font(.headline)
                Text("Edit the base language and each translated language side by side. Leave a cell empty to use the base language text.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)

            if items.isEmpty {
                Text("No text shapes in this project.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if translationLocales.isEmpty {
                Text("Add another language to edit translations here.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            headerColumn(
                                title: "Base Language",
                                subtitle: baseLocale?.flagLabel ?? state.localeState.baseLocaleCode.uppercased()
                            )
                            .frame(width: baseColumnWidth, alignment: .leading)
                            ForEach(translationLocales) { locale in
                                headerColumn(
                                    title: locale.flagLabel,
                                    subtitle: locale.code.uppercased()
                                )
                                .frame(width: translationColumnWidth, alignment: .leading)
                            }
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .background(.regularMaterial)

                        ForEach(items, id: \.shape.id) { item in
                            HStack(spacing: 0) {
                                baseColumn(
                                    shapeId: item.shape.id,
                                    text: item.shape.text ?? "",
                                    rowLabel: item.rowLabel
                                )
                                .frame(width: baseColumnWidth, alignment: .topLeading)

                                ForEach(translationLocales) { locale in
                                    TranslationMatrixCell(
                                        locale: locale,
                                        baseText: item.shape.text ?? "",
                                        text: Binding(
                                            get: {
                                                state.localeState.override(forCode: locale.code, shapeId: item.shape.id)?.text ?? ""
                                            },
                                            set: { newValue in
                                                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                                if trimmed.isEmpty {
                                                    state.resetTranslationText(shapeId: item.shape.id, localeCode: locale.code)
                                                } else {
                                                    state.updateTranslationText(
                                                        shapeId: item.shape.id,
                                                        localeCode: locale.code,
                                                        text: newValue
                                                    )
                                                }
                                            }
                                        ),
                                        columnPadding: columnPadding,
                                        isTranslating: isPendingTranslation(shapeId: item.shape.id, localeCode: locale.code),
                                        canReset: state.localeState.override(forCode: locale.code, shapeId: item.shape.id)?.text != nil,
                                        onTranslate: {
                                            startCellTranslation(
                                                shapeId: item.shape.id,
                                                localeCode: locale.code,
                                                baseText: item.shape.text ?? ""
                                            )
                                        },
                                        onReset: {
                                            state.resetTranslationText(shapeId: item.shape.id, localeCode: locale.code)
                                        }
                                    )
                                    .frame(width: translationColumnWidth, alignment: .topLeading)
                                }
                            }
                            .fixedSize(horizontal: true, vertical: false)
                            .background(Color(NSColor.textBackgroundColor))
                            Divider()
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 1120, height: 760)
        .translationTask(cellTranslationConfig) { session in
            guard let pendingCellTranslation else { return }
            defer { self.pendingCellTranslation = nil }
            do {
                let response = try await session.translate(pendingCellTranslation.baseText)
                state.updateTranslationText(
                    shapeId: pendingCellTranslation.shapeId,
                    localeCode: pendingCellTranslation.localeCode,
                    text: response.targetText
                )
            } catch {
                print("Translation failed for shape \(pendingCellTranslation.shapeId): \(error)")
            }
        }
    }

    private func headerColumn(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, columnPadding)
        .padding(.vertical, 10)
        .overlay(alignment: .trailing) {
            Divider()
        }
    }

    private func baseColumn(shapeId: UUID, text: String, rowLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Base text", text: Binding(
                get: { text },
                set: { state.updateBaseText(shapeId: shapeId, text: $0) }
            ), axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .lineLimit(2...6)
            Text(rowLabel)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .padding(columnPadding)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.55))
        .overlay(alignment: .trailing) {
            Divider()
        }
    }

    private func startCellTranslation(shapeId: UUID, localeCode: String, baseText: String) {
        let trimmed = baseText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingCellTranslation = PendingCellTranslation(
            shapeId: shapeId,
            localeCode: localeCode,
            baseText: trimmed
        )
        cellTranslationConfig.refresh(
            source: state.localeState.baseLocaleCode,
            target: localeCode
        )
    }

    private func isPendingTranslation(shapeId: UUID, localeCode: String) -> Bool {
        pendingCellTranslation?.shapeId == shapeId && pendingCellTranslation?.localeCode == localeCode
    }
}

private struct TranslationMatrixCell: View {
    let locale: LocaleDefinition
    let baseText: String
    @Binding var text: String
    let columnPadding: CGFloat
    let isTranslating: Bool
    let canReset: Bool
    let onTranslate: () -> Void
    let onReset: () -> Void
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("\(locale.flagLabel) text", text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .lineLimit(2...6)
                .help("Leave empty to use the base language text")
            if isHovered {
                HStack(spacing: 8) {
                    Button {
                        onTranslate()
                    } label: {
                        Label("Translate", systemImage: "globe")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                    .disabled(isTranslating || isUntranslated(baseText))

                    if canReset {
                        Button {
                            onReset()
                        } label: {
                            Label("Reset", systemImage: "arrow.uturn.backward")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .padding(columnPadding)
        .onHover { isHovered = $0 }
        .overlay(alignment: .trailing) {
            Divider()
        }
    }
}

private struct PendingCellTranslation: Equatable {
    let shapeId: UUID
    let localeCode: String
    let baseText: String
}
