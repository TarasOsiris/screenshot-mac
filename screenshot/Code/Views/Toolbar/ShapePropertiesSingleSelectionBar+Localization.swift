import SwiftUI

extension ShapePropertiesSingleSelectionBar {
    // MARK: - Localization Popover

    @ViewBuilder
    func textLocalizationButton(shape: CanvasShapeModel, shapeId: UUID) -> some View {
        Button {
            isTextLocalizationPopoverPresented.toggle()
        } label: {
            Image(systemName: "globe")
                .foregroundStyle(state.shapeHasActiveLocaleOverride(shapeId) ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.borderless)
        .help("Localization")
        .barPopover(isPresented: $isTextLocalizationPopoverPresented, title: "Localization") {
            #if os(macOS)
            textLocalizationPopoverContent(shape: shape, shapeId: shapeId)
                .padding(12)
                .frame(width: 320)
            #else
            TextLocalizationSheetContent(state: state, shapeId: shapeId, fallbackShape: shape)
            #endif
        }
    }

    #if os(macOS)
    @ViewBuilder
    func textLocalizationPopoverContent(shape: CanvasShapeModel, shapeId: UUID) -> some View {
        // The bar's `shape` is locale-resolved; read the base shape so the reference text and
        // translation key are correct even when editing a non-base locale.
        let baseShape = idx(for: shapeId).map { state.rows[$0.row].shapes[$0.shape] } ?? shape
        let baseText = baseShape.text ?? ""
        let hasBaseText = !baseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(state.localeState.baseLocaleLabel)
                    .font(.system(size: UIMetrics.FontSize.inlineLabel, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(hasBaseText ? baseText : String(localized: "Untitled text"))
                    .font(.system(size: UIMetrics.FontSize.body))
                    .foregroundStyle(hasBaseText ? Color.primary : Color.secondary)
                    .lineLimit(hasBaseText ? 2 : nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Fan-out translates *from* the base text into every language, so offer it only on the
            // base locale — firing it while editing a translation would overwrite that in-progress work.
            if state.localeState.isBaseLocale {
                Button {
                    state.pendingFanOutTranslateShapeIds = [shapeId]
                } label: {
                    HStack(spacing: 6) {
                        if state.isFanOutTranslating {
                            ProgressView().controlSize(.small)
                            Text("Translating…")
                        } else {
                            Image(systemName: "character.bubble")
                            Text("Translate into All Languages (\(state.localeState.nonBaseLocaleCount))")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(state.isFanOutTranslating || !hasBaseText)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(state.localeState.locales.dropFirst()) { locale in
                        localeTranslationRow(baseShape: baseShape, locale: locale)
                    }
                }
            }
            .frame(maxHeight: 240)

            Divider()

            reuseMenu(baseShape: baseShape, shapeId: shapeId)

            // Resets every language at once, so keep it on the base locale; per-language reset lives
            // on each row above for when you're editing a specific translation.
            if state.localeState.isBaseLocale {
                Button(role: .destructive) {
                    state.resetAllTranslations(shapeIds: [shapeId])
                } label: {
                    Label("Reset All Translations", systemImage: "arrow.counterclockwise")
                }
                .disabled(!state.anyTranslationOrOverride(shapeIds: [shapeId]))
            }

            HStack {
                Button("Edit Translation Table...") {
                    isTextLocalizationPopoverPresented = false
                    state.pendingLocaleMenuRequest = .editTranslations
                }
                Spacer()
                Button("Manage Languages...") {
                    isTextLocalizationPopoverPresented = false
                    state.pendingLocaleMenuRequest = .manageLocales
                }
            }
        }
        .font(.system(size: UIMetrics.FontSize.body))
        .controlSize(.small)
    }

    @ViewBuilder
    private func localeTranslationRow(baseShape: CanvasShapeModel, locale: LocaleDefinition) -> some View {
        let override = state.translationOverrideForDisplay(shape: baseShape, localeCode: locale.code)
        let formatted = formattedTranslationPlainText(for: override)
        let hasOverride = override?.hasTextContent == true

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(locale.flagLabel)
                    .font(.system(size: UIMetrics.FontSize.inlineLabel, weight: .semibold))
                Spacer()
                if hasOverride {
                    ActionButton(icon: "arrow.uturn.backward", tooltip: "Reset language override", frameSize: 20) {
                        state.resetTranslationText(shapeId: baseShape.id, localeCode: locale.code)
                    }
                }
            }

            if let formatted {
                Text(formatted.isEmpty ? String(localized: "Same as base language") : formatted)
                    .font(.system(size: UIMetrics.FontSize.body))
                    .foregroundStyle(formatted.isEmpty ? Color.secondary : Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Label("Formatted — edit on the canvas", systemImage: "paintbrush.pointed")
                    .font(.system(size: UIMetrics.FontSize.hint))
                    .foregroundStyle(.secondary)
            } else {
                // TextEditor-backed so Return inserts a newline (a vertical-axis TextField submits).
                MultilineCellEditor(
                    placeholder: String(localized: "Same as base language"),
                    text: localeTranslationBinding(state, shape: baseShape, localeCode: locale.code)
                )
            }
        }
    }

    @ViewBuilder
    private func reuseMenu(baseShape: CanvasShapeModel, shapeId: UUID) -> some View {
        reuseTranslationMenuContent(
            isLinked: baseShape.translationKey != nil,
            hasTargets: state.hasReusableTranslationTargets(excludingShapeId: shapeId),
            targets: {
                state.reusableTranslationTargets(excludingShapeId: shapeId)
                    .map { (key: $0.key, label: $0.baseText.singleLineMenuLabel()) }
            },
            onLink: { state.linkTranslation(shapeId: shapeId, toTargetKey: $0) },
            onUnlink: { state.unlinkTranslation(shapeId: shapeId) }
        )
        .menuStyle(.button)
    }
    #endif
}

#if os(iOS)
/// iPad variant of the per-text localization popover: `barPopover` presents it as a
/// detent sheet, so the content is a native inset-grouped list (like the iPad
/// Translation Table) instead of the dense desktop column — base text up top,
/// one editable row per language with swipe-to-reset, then reuse/reset/table actions.
private struct TextLocalizationSheetContent: View {
    let state: AppState
    let shapeId: UUID
    /// Locale-resolved shape from the bar, used only if the base shape lookup fails.
    let fallbackShape: CanvasShapeModel
    // Opening the Translation Table / Manage Languages from here is deferred to
    // onDisappear: LocaleBar can't present its sheet while this one is still dismissing.
    @State private var followUp: LocaleMenuRequest?
    @Environment(\.dismiss) private var dismiss

    private var baseShape: CanvasShapeModel {
        for row in state.rows {
            if let shape = row.shapes.first(where: { $0.id == shapeId }) { return shape }
        }
        return fallbackShape
    }

    var body: some View {
        let baseShape = baseShape
        let baseText = baseShape.text ?? ""
        let hasBaseText = !baseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        List {
            Section {
                if state.localeState.isBaseLocale {
                    Button {
                        state.pendingFanOutTranslateShapeIds = [shapeId]
                    } label: {
                        HStack(spacing: 8) {
                            if state.isFanOutTranslating {
                                ProgressView().controlSize(.small)
                                Text("Translating…")
                            } else {
                                Image(systemName: "character.bubble")
                                Text("Translate into All Languages (\(state.localeState.nonBaseLocaleCount))")
                            }
                        }
                    }
                    .disabled(state.isFanOutTranslating || !hasBaseText)
                }
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.localeState.baseLocaleLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                    Text(hasBaseText ? baseText : String(localized: "Untitled text"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(hasBaseText ? Color.primary : Color.secondary)
                        .lineLimit(3)
                        .textCase(nil)
                }
                .padding(.vertical, 4)
            }

            Section {
                ForEach(state.localeState.locales.dropFirst()) { locale in
                    translationRow(baseShape: baseShape, locale: locale)
                }
            }

            Section {
                reuseTranslationMenuContent(
                    isLinked: baseShape.translationKey != nil,
                    hasTargets: state.hasReusableTranslationTargets(excludingShapeId: shapeId),
                    targets: {
                        state.reusableTranslationTargets(excludingShapeId: shapeId)
                            .map { (key: $0.key, label: $0.baseText.singleLineMenuLabel()) }
                    },
                    onLink: { state.linkTranslation(shapeId: shapeId, toTargetKey: $0) },
                    onUnlink: { state.unlinkTranslation(shapeId: shapeId) }
                )

                // Resets every language at once, so keep it on the base locale; per-language
                // reset is the swipe action on each row above.
                if state.localeState.isBaseLocale {
                    Button(role: .destructive) {
                        state.resetAllTranslations(shapeIds: [shapeId])
                    } label: {
                        Label("Reset All Translations", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(!state.anyTranslationOrOverride(shapeIds: [shapeId]))
                }
            }

            Section {
                Button("Edit Translation Table...") {
                    followUp = .editTranslations
                    dismiss()
                }
                Button("Manage Languages...") {
                    followUp = .manageLocales
                    dismiss()
                }
            }
        }
        .listStyle(.insetGrouped)
        .onDisappear {
            if let followUp { state.pendingLocaleMenuRequest = followUp }
        }
    }

    @ViewBuilder
    private func translationRow(baseShape: CanvasShapeModel, locale: LocaleDefinition) -> some View {
        let override = state.translationOverrideForDisplay(shape: baseShape, localeCode: locale.code)
        let formatted = formattedTranslationPlainText(for: override)
        let hasOverride = override?.hasTextContent == true

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
                    text: localeTranslationBinding(state, shape: baseShape, localeCode: locale.code)
                )
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if hasOverride {
                Button(role: .destructive) {
                    state.resetTranslationText(shapeId: baseShape.id, localeCode: locale.code)
                } label: {
                    Label("Reset", systemImage: "arrow.uturn.backward")
                }
            }
        }
    }
}
#endif
