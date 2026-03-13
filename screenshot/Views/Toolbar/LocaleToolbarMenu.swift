import SwiftUI
import Translation

struct LocaleToolbarMenu: View {
    @Bindable var state: AppState
    @State private var isManagingLocales = false
    @State private var isTranslationOverview = false

    var body: some View {
        Menu {
            ForEach(state.localeState.locales) { locale in
                Button {
                    state.setActiveLocale(locale.code)
                } label: {
                    HStack(spacing: 8) {
                        Text(locale.label)
                        Text(locale.code.uppercased())
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                        Spacer()
                        if let progress = progressLabel(for: locale.code) {
                            Text(progress)
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
            if state.localeState.locales.count > 1 {
                Button("Previous Locale") {
                    state.cycleLocaleBackward()
                }

                Button("Next Locale") {
                    state.cycleLocaleForward()
                }
            }
            if !state.localeState.isBaseLocale {
                Button("Switch to Base Locale") {
                    state.setActiveLocale(state.localeState.baseLocaleCode)
                }
            }
            if state.localeState.locales.count > 1 && !state.localeState.isBaseLocale {
                Divider()
                Button("Translation Overview...") {
                    isTranslationOverview = true
                }
            }
            Divider()
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
                if let activeProgress = activeProgressLabel {
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
    }

    private var localeHelpText: String {
        if state.localeState.locales.count > 1 {
            return "Locale (\u{2318}[ / \u{2318}], \u{2325}\u{2318}0 to return to base)"
        }
        return "Locale"
    }

    private var activeProgressLabel: String? {
        guard !state.localeState.isBaseLocale else { return nil }
        let progress = state.translationProgress()
        guard progress.total > 0 else { return nil }
        return "\(progress.translated)/\(progress.total)"
    }

    private func progressLabel(for code: String) -> String? {
        guard code != state.localeState.baseLocaleCode else { return nil }
        let progress = state.translationProgress(for: code)
        guard progress.total > 0 else { return nil }
        return "\(progress.translated)/\(progress.total)"
    }
}

// MARK: - Non-base Locale Banner

struct LocaleBanner: View {
    @Bindable var state: AppState

    var body: some View {
        let localeState = state.localeState
        if !localeState.isBaseLocale {
            let label = localeState.activeLocaleLabel
            let progress = state.translationProgress()
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("Editing: \(label)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("Text changes apply to this locale only")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.accentColor.opacity(0.7))
                if progress.total > 0 {
                    Text("• \(progress.translated)/\(progress.total) translated")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.accentColor.opacity(0.7))
                }
                Spacer(minLength: 8)
                Button("Base Locale") {
                    state.setActiveLocale(localeState.baseLocaleCode)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .font(.system(size: 11, weight: .medium))
                .help("Switch to base locale (\u{2325}\u{2318}0)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(Color.accentColor.opacity(0.15))
        }
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
    @State private var showUntranslatedOnly = false
    @State private var translationConfig: TranslationSession.Configuration?
    @State private var translatingShapeIds: Set<UUID> = []

    var body: some View {
        let allItems = state.textShapesForTranslation()
        let items = showUntranslatedOnly
            ? allItems.filter { ($0.overrideText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            : allItems
        let activeLabel = state.localeState.activeLocaleLabel
        let progress = state.translationProgress()

        VStack(spacing: 0) {
            Text("Translation Overview — \(activeLabel)")
                .font(.headline)
                .padding(.top, 16)
                .padding(.bottom, 4)

            if !allItems.isEmpty {
                HStack(alignment: .center, spacing: 10) {
                    Text("\(progress.translated) of \(progress.total) text layers translated")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Spacer()

                    if progress.translated < progress.total {
                        Button {
                            let untranslated = allItems.filter {
                                ($0.overrideText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                && !(($0.shape.text ?? "").isEmpty)
                            }
                            translateShapes(Set(untranslated.map { $0.shape.id }))
                        } label: {
                            if !translatingShapeIds.isEmpty {
                                HStack(spacing: 4) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Translating...")
                                }
                            } else {
                                Label("Translate All", systemImage: "globe")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!translatingShapeIds.isEmpty)
                    }

                    Toggle("Untranslated only", isOn: $showUntranslatedOnly)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .font(.system(size: 11))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            if allItems.isEmpty {
                Text("No text shapes in this project.")
                    .foregroundStyle(.secondary)
                    .frame(maxHeight: .infinity)
            } else if items.isEmpty {
                Text("All text layers are translated.")
                    .foregroundStyle(.secondary)
                    .frame(maxHeight: .infinity)
            } else {
                // Header
                HStack(spacing: 0) {
                    Text("Base text")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(activeLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 4)

                List {
                    ForEach(items, id: \.shape.id) { item in
                        TranslationRow(
                            baseText: item.shape.text ?? "",
                            rowLabel: item.rowLabel,
                            overrideText: item.overrideText ?? "",
                            localeLabel: activeLabel,
                            isTranslating: translatingShapeIds.contains(item.shape.id),
                            onUpdate: { newText in
                                state.updateTranslationText(shapeId: item.shape.id, text: newText)
                            },
                            onTranslate: {
                                translateShapes([item.shape.id])
                            },
                            onJump: {
                                state.focusShapeOnCanvas(shapeId: item.shape.id, rowId: item.rowId)
                                dismiss()
                            }
                        )
                    }
                }
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(width: 600, height: 420)
        .translationTask(translationConfig) { session in
            defer { translatingShapeIds.removeAll() }
            let allItems = state.textShapesForTranslation()
            for item in allItems where translatingShapeIds.contains(item.shape.id) {
                guard let baseText = item.shape.text, !baseText.isEmpty else { continue }
                do {
                    let response = try await session.translate(baseText)
                    state.updateTranslationText(shapeId: item.shape.id, text: response.targetText)
                } catch {
                    print("Translation failed for shape \(item.shape.id): \(error)")
                }
            }
        }
    }

    private func translateShapes(_ shapeIds: Set<UUID>) {
        translatingShapeIds = shapeIds
        translationConfig.refresh(
            source: state.localeState.baseLocaleCode,
            target: state.localeState.activeLocaleCode
        )
    }
}

private struct TranslationRow: View {
    let baseText: String
    let rowLabel: String
    private let initialOverrideText: String
    @State private var overrideText: String
    let localeLabel: String
    let isTranslating: Bool
    let onUpdate: (String) -> Void
    let onTranslate: () -> Void
    let onJump: () -> Void

    init(
        baseText: String,
        rowLabel: String,
        overrideText: String,
        localeLabel: String,
        isTranslating: Bool,
        onUpdate: @escaping (String) -> Void,
        onTranslate: @escaping () -> Void,
        onJump: @escaping () -> Void
    ) {
        self.baseText = baseText
        self.rowLabel = rowLabel
        self.initialOverrideText = overrideText
        self._overrideText = State(initialValue: overrideText)
        self.localeLabel = localeLabel
        self.isTranslating = isTranslating
        self.onUpdate = onUpdate
        self.onTranslate = onTranslate
        self.onJump = onJump
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(baseText.isEmpty ? "Empty text layer" : baseText)
                    .font(.system(size: 12))
                    .lineLimit(3)
                Text(rowLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 4) {
                TextField("\(localeLabel) translation...", text: $overrideText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .lineLimit(1...3)
                    .frame(maxWidth: .infinity)
                    .onChange(of: overrideText) { _, newValue in
                        onUpdate(newValue)
                    }
                    .onChange(of: initialOverrideText) { _, newValue in
                        if overrideText != newValue {
                            overrideText = newValue
                        }
                    }

                HStack(spacing: 8) {
                    Button {
                        onTranslate()
                    } label: {
                        if isTranslating {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 12, height: 12)
                        } else {
                            Label("Translate", systemImage: "globe")
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                    .disabled(baseText.isEmpty || isTranslating)

                    Button("Use Base") {
                        overrideText = baseText
                        onUpdate(baseText)
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                    .disabled(baseText.isEmpty)

                    Button("Clear") {
                        overrideText = ""
                        onUpdate("")
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                    .disabled(overrideText.isEmpty)

                    Spacer()

                    Button {
                        onJump()
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Jump to canvas")
                    .accessibilityLabel("Jump to canvas")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
