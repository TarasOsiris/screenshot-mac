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

    var body: some View {
        let progress = state.translationProgress()
        Menu {
            ForEach(state.localeState.locales) { locale in
                Button {
                    state.setActiveLocale(locale.code)
                } label: {
                    HStack(spacing: 8) {
                        Text(locale.code == state.localeState.baseLocaleCode ? "\(locale.label) (base)" : locale.label)
                        Text(locale.code.uppercased())
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                        Spacer()
                        if let progressLabel = progressLabel(for: locale.code) {
                            Text(progressLabel)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        if locale.code == state.localeState.activeLocaleCode {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            Divider()
            if !state.localeState.isBaseLocale {
                Button("Switch to Base Language") {
                    state.setActiveLocale(state.localeState.baseLocaleCode)
                }
            }
            if !state.localeState.isBaseLocale {
                Divider()
                Button("Fill Missing Text with Translation") {
                    startQuickTranslation(onlyUntranslated: true)
                }
                .disabled(
                    isQuickTranslating ||
                    progress.total == 0 ||
                    progress.translated >= progress.total
                )

                Button("Replace All Text with Translation...") {
                    showReplaceAllConfirmation = true
                }
                .disabled(isQuickTranslating || progress.total == 0)

                Button("Reset All Text and Images to Base Language...", role: .destructive) {
                    showResetToBaseConfirmation = true
                }
                .disabled(isQuickTranslating || !activeLocaleHasOverrides)
            }
            Divider()
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
                    .foregroundStyle(state.localeState.isBaseLocale ? .secondary : Color.accentColor)
                Text(state.localeState.activeLocaleLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(state.localeState.isBaseLocale ? .secondary : Color.accentColor)
                if let untranslatedLabel = untranslatedLabel(progress: progress) {
                    Text(untranslatedLabel)
                        .font(.system(size: 10, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.14), in: Capsule())
                        .foregroundStyle(Color.orange)
                }
                if let activeProgress = activeProgressLabel(progress: progress) {
                    Text(activeProgress)
                        .font(.system(size: 10, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
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
            Button("Reset to Base Language", role: .destructive) {
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
            await translateShapes(
                session: session,
                state: state,
                targetLocaleCode: targetLocaleCode,
                onlyUntranslated: quickTranslateOnlyUntranslated
            )
        }
    }

    private var localeHelpText: String {
        if state.localeState.locales.count > 1 {
            return "Language (\u{2318}[ / \u{2318}], \u{2325}\u{2318}0 to switch to the base language)"
        }
        return "Language"
    }

    private func activeProgressLabel(progress: (translated: Int, total: Int)) -> String? {
        guard !state.localeState.isBaseLocale else { return nil }
        guard progress.total > 0 else { return nil }
        return "\(progress.translated)/\(progress.total)"
    }

    private func untranslatedLabel(progress: (translated: Int, total: Int)) -> String? {
        guard !state.localeState.isBaseLocale else { return nil }
        let missing = max(progress.total - progress.translated, 0)
        guard missing > 0 else { return nil }
        return "\(missing) left"
    }

    private var activeLocaleHasOverrides: Bool {
        guard !state.localeState.isBaseLocale else { return false }
        return !(state.localeState.overrides[state.localeState.activeLocaleCode]?.isEmpty ?? true)
    }

    private func progressLabel(for code: String) -> String? {
        guard code != state.localeState.baseLocaleCode else { return nil }
        let progress = state.translationProgress(for: code)
        guard progress.total > 0 else { return nil }
        return "\(progress.translated)/\(progress.total)"
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
    @State private var showReplaceAllConfirmation = false
    @State private var showResetToBaseConfirmation = false
    @State private var isTranslationOverviewPresented = false

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
                        .foregroundStyle(Color.accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Editing \(label)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                            if progress.total > 0 {
                                Text("\(progress.translated)/\(progress.total)")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                                    .foregroundStyle(Color.accentColor)
                            }
                            if missingCount > 0 {
                                Text("\(missingCount) left")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.14), in: Capsule())
                                    .foregroundStyle(Color.orange)
                            }
                        }
                        Text("Changes here affect only \(label). Edit translations manually, fill in missing text automatically, or switch back to the base language.")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.accentColor.opacity(0.72))
                    }

                    Spacer(minLength: 8)

                    if progress.total > 0 {
                        Button("Edit Table") {
                            isTranslationOverviewPresented = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .font(.system(size: 11, weight: .medium))

                        Menu {
                            Button("Fill Missing Text with Translation") {
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
                                Label("Translate Text", systemImage: "globe")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .font(.system(size: 11, weight: .medium))
                        .disabled(isTranslating)
                    }

                    Button("Switch to Base Language") {
                        state.setActiveLocale(localeState.baseLocaleCode)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .font(.system(size: 11, weight: .medium))
                    .help("Switch to the base language (\u{2325}\u{2318}0)")

                    Button("Reset to Base Language", role: .destructive) {
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
            .background(Color.accentColor.opacity(0.15))
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
                Button("Reset to Base Language", role: .destructive) {
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
                await translateShapes(
                    session: session,
                    state: state,
                    targetLocaleCode: targetLocaleCode,
                    onlyUntranslated: translateOnlyUntranslated
                )
            }
        }
    }

    private func startTranslation(onlyUntranslated: Bool) {
        translateOnlyUntranslated = onlyUntranslated
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
            Text("Manage Locales")
                .font(.headline)
                .padding(.top, 16)
                .padding(.bottom, 12)

            List {
                ForEach(state.localeState.locales) { locale in
                    let progress = state.translationProgress(for: locale.code)
                    HStack {
                        Text(locale.code)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 36, alignment: .leading)
                        Text(locale.label)
                        Spacer()
                        if locale.code == state.localeState.baseLocaleCode {
                            Text("Base")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            if progress.total > 0 {
                                Text("\(progress.translated)/\(progress.total)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
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
            .frame(minHeight: 120)

            Text("First locale is base. Drag other locales to reorder export folders.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 6)

            Divider()

            VStack(spacing: 8) {
                Button("Add Language...") {
                    showPresets = true
                }
                .buttonStyle(.borderless)
            }
            .padding(12)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(width: 360, height: 320)
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
                        Text(locale.label)
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
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
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
                        } header: {
                            HStack(spacing: 0) {
                                headerColumn(
                                    title: "Base Language",
                                    subtitle: baseLocale?.label ?? state.localeState.baseLocaleCode.uppercased()
                                )
                                .frame(width: baseColumnWidth, alignment: .leading)
                                ForEach(translationLocales) { locale in
                                    headerColumn(
                                        title: locale.label,
                                        subtitle: locale.code.uppercased()
                                    )
                                    .frame(width: translationColumnWidth, alignment: .leading)
                                }
                            }
                            .fixedSize(horizontal: true, vertical: false)
                            .background(.regularMaterial)
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
            TextField("\(locale.label) text", text: $text, axis: .vertical)
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
