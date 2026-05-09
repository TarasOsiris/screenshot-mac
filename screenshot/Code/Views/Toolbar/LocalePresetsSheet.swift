import SwiftUI

struct ManageLocalesSheet: View {
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
