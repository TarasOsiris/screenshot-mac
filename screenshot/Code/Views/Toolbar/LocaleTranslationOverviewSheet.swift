import OSLog
import SwiftUI
import Translation

struct TranslationOverviewSheet: View {
    private static let title: LocalizedStringKey = "Edit Translations"
    @Bindable var state: AppState
    #if os(macOS)
    @Environment(\.dismiss) private var dismiss
    #endif
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
                #if os(macOS)
                Text(Self.title)
                    .font(.headline)
                #endif
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

            #if os(macOS)
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            #endif
        }
        #if os(macOS)
        .frame(width: 1120, height: 760)
        #endif
        .iosSheetChrome(Text(Self.title))
        .translationTask(cellTranslationConfig) { session in
            guard let pendingCellTranslation else { return }
            defer { self.pendingCellTranslation = nil }
            do {
                let translatedText = try await translatePreservingLineBreaks(pendingCellTranslation.baseText) { text in
                    let response = try await session.translate(text)
                    return response.targetText
                }
                state.updateTranslationText(
                    shapeId: pendingCellTranslation.shapeId,
                    localeCode: pendingCellTranslation.localeCode,
                    text: translatedText
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
            .background(Color.platformTextBackground)

            Divider()
        }
    }

    private func baseColumn(shapeId: UUID, text: String, rowLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            MultilineCellEditor(
                placeholder: "Base text",
                text: Binding(
                    get: { text },
                    set: { state.updateBaseText(shapeId: shapeId, text: $0) }
                )
            )
            Text(rowLabel)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .padding(columnPadding)
        .background(Color.platformControlBackground.opacity(0.55))
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
            MultilineCellEditor(
                placeholder: "\(locale.flagLabel) text",
                text: $text,
                help: "Leave empty to use the base language text"
            )
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

/// Multiline editor that uses `TextEditor` so Return inserts a newline (a
/// vertical-axis `TextField` treats Return as a submit gesture on macOS).
private struct MultilineCellEditor: View {
    let placeholder: String
    @Binding var text: String
    var help: String? = nil

    // Local buffer: binding TextEditor straight to AppState-backed state recomputes
    // the body on every keystroke and re-feeds the value, resetting the caret to the
    // end. The buffer survives recomputes; we sync to/from `text` only on real changes.
    @State private var localText: String
    @State private var contentHeight: CGFloat = 0

    private let fontSize: CGFloat = 12
    // Match the TextEditor's intrinsic text origin so the placeholder/mirror align.
    private let insetH: CGFloat = 5
    private let insetV: CGFloat = 5
    private let minHeight: CGFloat = 40   // ~2 lines
    private let maxHeight: CGFloat = 100  // ~6 lines

    init(placeholder: String, text: Binding<String>, help: String? = nil) {
        self.placeholder = placeholder
        self._text = text
        self.help = help
        self._localText = State(initialValue: text.wrappedValue)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Invisible mirror sizes the editor so it grows with the text instead
            // of clipping at a fixed height; shares the editor's width and insets.
            Text(localText.isEmpty ? placeholder : localText)
                .font(.system(size: fontSize))
                .padding(.horizontal, insetH)
                .padding(.vertical, insetV)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: CellHeightKey.self, value: proxy.size.height)
                })
                .hidden()

            if localText.isEmpty {
                Text(placeholder)
                    .font(.system(size: fontSize))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, insetH)
                    .padding(.vertical, insetV)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $localText)
                .font(.system(size: fontSize))
                .scrollContentBackground(.hidden)
        }
        .frame(height: min(max(contentHeight, minHeight), maxHeight))
        .onPreferenceChange(CellHeightKey.self) { contentHeight = $0 }
        .onChange(of: localText) { _, newValue in
            if newValue != text { text = newValue }
        }
        .onChange(of: text) { _, newValue in
            if newValue != localText { localText = newValue }
        }
        .background(Color.platformTextBackground)
        .overlay(
            RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.card)
                .stroke(Color.platformSeparator, lineWidth: UIMetrics.BorderWidth.standard)
        )
        .clipShape(RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.card))
        .modifier(OptionalHelp(help: help))
    }
}

/// Intrinsic content height of a cell editor, used to size it to fit.
private struct CellHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct OptionalHelp: ViewModifier {
    let help: String?

    func body(content: Content) -> some View {
        if let help {
            content.help(help)
        } else {
            content
        }
    }
}

private struct PendingCellTranslation: Equatable {
    let shapeId: UUID
    let localeCode: String
    let baseText: String
}
