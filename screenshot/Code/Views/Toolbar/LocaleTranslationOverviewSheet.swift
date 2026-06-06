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
    // Serial queue: concurrent taps enqueue; one cell translates at a time because the
    // session config holds a single language pair and refreshing it cancels the running task.
    @State private var cellTranslationQueue: [PendingCellTranslation] = []
    @State private var isProcessingCellTranslation = false
    private let baseColumnWidth: CGFloat = 320
    private let translationColumnWidth: CGFloat = 260
    private let columnPadding: CGFloat = 12

    var body: some View {
        platformContent
            .onAppear {
                // Any in-flight task died with the previous appearance; drop its stale state.
                cellTranslationQueue.removeAll()
                isProcessingCellTranslation = false
            }
            .translationTask(cellTranslationConfig) { session in
                guard let item = cellTranslationQueue.first else {
                    isProcessingCellTranslation = false
                    return
                }
                do {
                    let translatedText = try await translatePreservingLineBreaks(item.baseText) { text in
                        let response = try await session.translate(text)
                        return response.targetText
                    }
                    state.updateTranslationText(
                        shapeId: item.shapeId,
                        localeCode: item.localeCode,
                        text: translatedText
                    )
                } catch {
                    AppLogger.translation.error("Translation failed for shape \(item.shapeId, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
                // Dequeue by identity, not position — survives any cancel/re-fire interleaving.
                cellTranslationQueue.removeAll { $0.shapeId == item.shapeId && $0.localeCode == item.localeCode }
                isProcessingCellTranslation = false
                processNextCellTranslationIfIdle()
            }
    }

    #if os(macOS)
    private var platformContent: some View {
        let items = state.textShapesForTranslationMatrix()
        let baseLocale = state.localeState.locales.first
        let translationLocales = Array(state.localeState.locales.dropFirst())

        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.title)
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
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 1120, height: 760)
    }
    #else
    // iPad: a native inset-grouped list — one section per string (header is the base
    // text), each language an inline buffered field. Translate is a visible button;
    // Reset is a trailing swipe. Replaces the hover-driven horizontal matrix.
    private var platformContent: some View {
        let items = state.textShapesForTranslationMatrix()
        let translationLocales = Array(state.localeState.locales.dropFirst())

        return Group {
            if items.isEmpty {
                ContentUnavailableView(
                    "No Text to Translate",
                    systemImage: "textformat",
                    description: Text("This project has no text shapes yet.")
                )
            } else if translationLocales.isEmpty {
                ContentUnavailableView(
                    "No Languages Added",
                    systemImage: "globe",
                    description: Text("Add another language to edit translations here.")
                )
            } else {
                List {
                    ForEach(items, id: \.shape.id) { item in
                        Section {
                            ForEach(translationLocales) { locale in
                                iosTranslationRow(item: item, locale: locale)
                            }
                        } header: {
                            iosSectionHeader(item: item)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .iosSheetChrome(Text(Self.title))
    }

    @ViewBuilder
    private func iosSectionHeader(item: (shape: CanvasShapeModel, rowLabel: String)) -> some View {
        let baseText = (item.shape.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        VStack(alignment: .leading, spacing: 2) {
            Text(baseText.isEmpty ? String(localized: "Untitled text") : baseText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .textCase(nil)
            if !item.rowLabel.isEmpty {
                Text(item.rowLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func iosTranslationRow(
        item: (shape: CanvasShapeModel, rowLabel: String),
        locale: LocaleDefinition
    ) -> some View {
        let baseText = item.shape.text ?? ""
        let hasOverride = state.localeState.override(forCode: locale.code, shapeId: item.shape.id)?.text != nil
        let translating = isPendingTranslation(shapeId: item.shape.id, localeCode: locale.code)

        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(locale.flagLabel)
                    .font(.subheadline.weight(.semibold))

                BufferedTranslationField(
                    placeholder: String(localized: "Same as base language"),
                    text: translationTextBinding(shapeId: item.shape.id, localeCode: locale.code)
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                startCellTranslation(
                    shapeId: item.shape.id,
                    localeCode: locale.code,
                    baseText: baseText
                )
            } label: {
                Group {
                    if translating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Translate", systemImage: "translate")
                    }
                }
                .frame(minHeight: UIMetrics.CapsuleButton.minContentHeight)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .disabled(translating || isUntranslated(baseText))
            .accessibilityLabel("Translate to \(locale.flagLabel)")
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if hasOverride {
                Button(role: .destructive) {
                    state.resetTranslationText(shapeId: item.shape.id, localeCode: locale.code)
                } label: {
                    Label("Reset", systemImage: "arrow.uturn.backward")
                }
            }
        }
    }
    #endif

    #if os(macOS)
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
                        text: translationTextBinding(shapeId: item.shape.id, localeCode: locale.code),
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
    #endif

    /// Override text for one cell; setting a blank value resets to the base language.
    private func translationTextBinding(shapeId: UUID, localeCode: String) -> Binding<String> {
        Binding(
            get: {
                state.localeState.override(forCode: localeCode, shapeId: shapeId)?.text ?? ""
            },
            set: { newValue in
                if isUntranslated(newValue) {
                    state.resetTranslationText(shapeId: shapeId, localeCode: localeCode)
                } else {
                    state.updateTranslationText(
                        shapeId: shapeId,
                        localeCode: localeCode,
                        text: newValue
                    )
                }
            }
        )
    }

    private func startCellTranslation(shapeId: UUID, localeCode: String, baseText: String) {
        let trimmed = baseText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !cellTranslationQueue.contains(where: { $0.shapeId == shapeId && $0.localeCode == localeCode }) else { return }
        cellTranslationQueue.append(PendingCellTranslation(
            shapeId: shapeId,
            localeCode: localeCode,
            baseText: trimmed
        ))
        processNextCellTranslationIfIdle()
    }

    private func processNextCellTranslationIfIdle() {
        guard !isProcessingCellTranslation, let next = cellTranslationQueue.first else { return }
        isProcessingCellTranslation = true
        cellTranslationConfig.refresh(
            source: state.localeState.baseLocaleCode,
            target: next.localeCode
        )
    }

    private func isPendingTranslation(shapeId: UUID, localeCode: String) -> Bool {
        cellTranslationQueue.contains { $0.shapeId == shapeId && $0.localeCode == localeCode }
    }
}

#if os(macOS)
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
#endif

#if os(iOS)
/// Buffers edits locally so binding straight to @Observable AppState doesn't reset the
/// caret on every keystroke (the body recomputes and re-feeds the value otherwise).
private struct BufferedTranslationField: View {
    let placeholder: String
    @Binding var text: String
    @State private var localText: String

    init(placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        self._text = text
        self._localText = State(initialValue: text.wrappedValue)
    }

    var body: some View {
        TextField(placeholder, text: $localText, axis: .vertical)
            .lineLimit(1...6)
            .onChange(of: localText) { _, newValue in
                if newValue != text { text = newValue }
            }
            .onChange(of: text) { _, newValue in
                if newValue != localText { localText = newValue }
            }
    }
}
#endif

private struct PendingCellTranslation {
    let shapeId: UUID
    let localeCode: String
    let baseText: String
}
