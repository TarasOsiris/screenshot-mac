import OSLog
import SwiftUI
import Translation

struct TranslationOverviewSheet: View {
    private static let title: LocalizedStringKey = "Edit Translations"
    @Bindable var state: AppState
    #if os(macOS)
    @Environment(\.dismiss) private var dismiss
    // Only the actively-edited cell mounts a live TextEditor; every other cell shows a
    // cheap preview, so a large terms × languages matrix stays smooth to scroll.
    @State private var editingCellId: MatrixCellID?
    #endif
    @State private var cellTranslationConfig: TranslationSession.Configuration?
    // Serial queue: concurrent taps enqueue; one cell translates at a time because the
    // session config holds a single language pair and refreshing it cancels the running task.
    @State private var cellTranslationQueue: [PendingCellTranslation] = []
    @State private var isProcessingCellTranslation = false
    @State private var languageIssue: TranslationLanguageIssue?
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
                if let blocked = await ensureTranslationAvailable(
                    session: session,
                    source: state.localeState.baseLocaleCode,
                    target: item.localeCode
                ) {
                    languageIssue = TranslationLanguageIssue(blocked, language: state.localeState.languageLabel(for: item.localeCode))
                    cellTranslationQueue.removeAll { $0.shapeId == item.shapeId && $0.localeCode == item.localeCode }
                    isProcessingCellTranslation = false
                    processNextCellTranslationIfIdle()
                    return
                }
                do {
                    let translatedText = try await translatePreservingLineBreaks(item.baseText) { text in
                        let response = try await session.translate(text)
                        return try validatedTargetText(response, requestedTarget: item.localeCode)
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
            .translationLanguageIssueAlert(item: $languageIssue)
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
                ScrollView([.horizontal, .vertical]) {
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
        let override = state.translationOverrideForDisplay(shape: item.shape, localeCode: locale.code)
        let formatted = formattedTranslationPlainText(for: override)
        let hasOverride = override?.hasTextContent == true
        let translating = isPendingTranslation(shapeId: item.shape.id, localeCode: locale.code)

        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(locale.flagLabel)
                    .font(.subheadline.weight(.semibold))

                if let formatted {
                    Text(formatted.isEmpty ? String(localized: "Same as base language") : formatted)
                        .font(.body)
                        .foregroundStyle(formatted.isEmpty ? Color.secondary : Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Label("Formatted — edit on the canvas", systemImage: "paintbrush.pointed")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    BufferedTranslationField(
                        placeholder: String(localized: "Same as base language"),
                        text: localeTranslationBinding(state, shape: item.shape, localeCode: locale.code)
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if formatted == nil {
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
                baseColumn(shape: item.shape, rowLabel: item.rowLabel)
                .frame(width: baseColumnWidth, alignment: .topLeading)

                ForEach(locales) { locale in
                    let override = state.translationOverrideForDisplay(shape: item.shape, localeCode: locale.code)
                    TranslationMatrixCell(
                        locale: locale,
                        baseText: item.shape.text ?? "",
                        text: localeTranslationBinding(state, shape: item.shape, localeCode: locale.code),
                        formattedPlainText: formattedTranslationPlainText(for: override),
                        cellId: MatrixCellID(shapeId: item.shape.id, localeCode: locale.code),
                        editingCellId: $editingCellId,
                        columnPadding: columnPadding,
                        isTranslating: isPendingTranslation(shapeId: item.shape.id, localeCode: locale.code),
                        canReset: override?.hasTextContent == true,
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

    private func baseColumn(shape: CanvasShapeModel, rowLabel: String) -> some View {
        let cellId = MatrixCellID(shapeId: shape.id, localeCode: nil)
        return VStack(alignment: .leading, spacing: 6) {
            if editingCellId == cellId {
                MultilineCellEditor(
                    placeholder: "Base text",
                    text: Binding(
                        get: { shape.text ?? "" },
                        set: { state.updateBaseText(shapeId: shape.id, text: $0) }
                    ),
                    autofocus: true,
                    // Only clear if still ours: tapping another cell already moved editing on.
                    onEditingEnded: { if editingCellId == cellId { editingCellId = nil } }
                )
            } else {
                MatrixCellPreview(text: shape.text ?? "", placeholder: "Base text")
                    .onTapGesture { editingCellId = cellId }
            }
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
/// Identifies the one matrix cell currently being edited. `localeCode == nil` is the base column.
struct MatrixCellID: Hashable {
    let shapeId: UUID
    let localeCode: String?
}

private struct TranslationMatrixCell: View {
    let locale: LocaleDefinition
    let baseText: String
    @Binding var text: String
    /// Non-nil when this translation carries custom formatting; shown read-only.
    let formattedPlainText: String?
    let cellId: MatrixCellID
    @Binding var editingCellId: MatrixCellID?
    let columnPadding: CGFloat
    let isTranslating: Bool
    let canReset: Bool
    let onTranslate: () -> Void
    let onReset: () -> Void
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let formattedPlainText {
                formattedReadOnlyCell(formattedPlainText)
            } else if editingCellId == cellId {
                MultilineCellEditor(
                    placeholder: "\(locale.flagLabel) text",
                    text: $text,
                    help: "Leave empty to use the base language text",
                    autofocus: true,
                    // Only clear if still ours: tapping another cell already moved editing on.
                    onEditingEnded: { if editingCellId == cellId { editingCellId = nil } }
                )
            } else {
                MatrixCellPreview(
                    text: text,
                    placeholder: "\(locale.flagLabel) text",
                    help: "Leave empty to use the base language text"
                )
                .onTapGesture { editingCellId = cellId }
            }
            if isHovered {
                HStack(spacing: 8) {
                    // Translating would replace the formatted text with plain text, so offer it
                    // only for plain cells; edit formatted translations on the canvas instead.
                    if formattedPlainText == nil {
                        Button {
                            onTranslate()
                        } label: {
                            Label("Translate", systemImage: "globe")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.borderless)
                        .disabled(isTranslating || isUntranslated(baseText))
                    }

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

    @ViewBuilder
    private func formattedReadOnlyCell(_ plain: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(plain.isEmpty ? String(localized: "Same as base language") : plain)
                .font(.system(size: 12))
                .foregroundStyle(plain.isEmpty ? Color.secondary : Color.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, minHeight: CellEditorStyle.minHeight, alignment: .topLeading)
                .padding(.horizontal, CellEditorStyle.insetH)
                .padding(.vertical, CellEditorStyle.insetV)
                .cellEditorChrome()

            Label("Formatted — edit on the canvas", systemImage: "paintbrush.pointed")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .help("This translation uses custom formatting (colors, bold, sizes). The table edits plain text only — edit it directly on the canvas, or Reset to use the base language.")
        }
    }
}
#endif

private struct PendingCellTranslation {
    let shapeId: UUID
    let localeCode: String
    let baseText: String
}
