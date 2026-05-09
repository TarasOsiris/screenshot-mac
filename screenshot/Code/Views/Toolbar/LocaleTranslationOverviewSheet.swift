import OSLog
import SwiftUI
import Translation

struct TranslationOverviewSheet: View {
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
                ScrollView(.horizontal) {
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                            Section {
                                ForEach(items, id: \.shape.id) { item in
                                    translationRow(item: item, locales: translationLocales)
                                }
                            } header: {
                                translationHeaderRow(baseLocale: baseLocale, locales: translationLocales)
                            }
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
                AppLogger.translation.error("Translation failed for shape \(pendingCellTranslation.shapeId, privacy: .public): \(error.localizedDescription, privacy: .public)")
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

    private func translationHeaderRow(
        baseLocale: LocaleDefinition?,
        locales: [LocaleDefinition]
    ) -> some View {
        HStack(spacing: 0) {
            headerColumn(
                title: "Base Language",
                subtitle: baseLocale?.flagLabel ?? state.localeState.baseLocaleCode.uppercased()
            )
            .frame(width: baseColumnWidth, alignment: .leading)

            ForEach(locales) { locale in
                headerColumn(
                    title: locale.flagLabel,
                    subtitle: locale.code.uppercased()
                )
                .frame(width: translationColumnWidth, alignment: .leading)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .background(.regularMaterial)
    }

    private func translationRow(
        item: (shape: CanvasShapeModel, rowLabel: String),
        locales: [LocaleDefinition]
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                baseColumn(
                    shapeId: item.shape.id,
                    text: item.shape.text ?? "",
                    rowLabel: item.rowLabel
                )
                .frame(width: baseColumnWidth, alignment: .topLeading)

                ForEach(locales) { locale in
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
