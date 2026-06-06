import SwiftUI

struct ManageLocalesSheet: View {
    private static let title: LocalizedStringKey = "Manage Languages"
    @Bindable var state: AppState
    #if os(macOS)
    @Environment(\.dismiss) private var dismiss
    #endif
    @State private var searchText = ""
    @State private var showPresets = false

    var body: some View {
        platformContent
            .iosSheetChrome(Text(Self.title))
            .sheet(isPresented: $showPresets) {
                LocalePresetsSheet(state: state, searchText: $searchText)
            }
    }

    #if os(macOS)
    private var platformContent: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text(Self.title)
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
                                .padding(.horizontal, UIMetrics.StatusBadge.horizontalPadding)
                                .padding(.vertical, UIMetrics.StatusBadge.verticalPadding)
                                .background(Color.accentColor.opacity(UIMetrics.Opacity.accentBadge), in: Capsule())
                                .foregroundStyle(Color.accentColor)
                        } else {
                            if progress.total > 0 {
                                let statusColor: Color = progress.translated >= progress.total ? .green : .orange
                                Text("\(progress.translated)/\(progress.total)")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .padding(.horizontal, UIMetrics.StatusBadge.horizontalPadding)
                                    .padding(.vertical, UIMetrics.StatusBadge.verticalPadding)
                                    .background(statusColor.opacity(UIMetrics.Opacity.accentBadge), in: Capsule())
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
                            .help("Delete language")
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
    }
    #else
    // iPad: native inset-grouped manage list (Settings ▸ Preferred Languages pattern) —
    // swipe or Edit mode to delete, drag to reorder, "Add Language" as a tappable row.
    private var platformContent: some View {
        List {
            Section {
                ForEach(state.localeState.locales) { locale in
                    iosLocaleRow(locale)
                }
                .onMove { source, destination in
                    state.moveLocale(from: source, to: destination)
                }
                .onDelete { offsets in
                    let codes = offsets.map { state.localeState.locales[$0].code }
                    codes.forEach { state.removeLocale($0) }
                }

                Button {
                    searchText = ""
                    showPresets = true
                } label: {
                    Label("Add Language", systemImage: "plus")
                }
            } footer: {
                Text("The first language is the base. Drag to reorder.")
            }
        }
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
        }
    }

    @ViewBuilder
    private func iosLocaleRow(_ locale: LocaleDefinition) -> some View {
        let isBase = locale.code == state.localeState.baseLocaleCode
        let progress = state.translationProgress(for: locale.code)

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(locale.flagLabel)
                Text(locale.code.uppercased())
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isBase {
                Text("Base")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, UIMetrics.StatusBadge.horizontalPadding)
                    .padding(.vertical, UIMetrics.StatusBadge.verticalPadding)
                    .background(Color.accentColor.opacity(UIMetrics.Opacity.accentBadge), in: Capsule())
                    .foregroundStyle(Color.accentColor)
            } else if progress.total > 0 {
                let statusColor: Color = progress.translated >= progress.total ? .green : .orange
                Text("\(progress.translated)/\(progress.total)")
                    .font(.caption.weight(.medium).monospaced())
                    .padding(.horizontal, UIMetrics.StatusBadge.horizontalPadding)
                    .padding(.vertical, UIMetrics.StatusBadge.verticalPadding)
                    .background(statusColor.opacity(UIMetrics.Opacity.accentBadge), in: Capsule())
                    .foregroundStyle(statusColor)
            }
        }
        .deleteDisabled(isBase)
    }
    #endif
}

private struct LocalePresetsSheet: View {
    private static let title: LocalizedStringKey = "Add Language"
    @Bindable var state: AppState
    @Binding var searchText: String
    #if os(macOS)
    @Environment(\.dismiss) private var dismiss
    #endif

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
        platformContent
            .iosSheetChrome(Text(Self.title))
    }

    #if os(macOS)
    private var platformContent: some View {
        VStack(spacing: 0) {
            Text(Self.title)
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
    #else
    // iPad: tap a row to add it (it leaves the list as feedback); search lives in the nav bar.
    private var platformContent: some View {
        List {
            ForEach(availablePresets) { locale in
                Button {
                    state.addLocale(locale)
                } label: {
                    HStack(spacing: 12) {
                        Text(locale.flagLabel)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(locale.code.uppercased())
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text("Search languages...")
        )
        .overlay {
            if availablePresets.isEmpty && !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }
    #endif
}
