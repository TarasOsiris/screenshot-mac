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
            textLocalizationPopoverContent(shape: shape, shapeId: shapeId)
                .padding(12)
                .frame(width: 320)
        }
    }

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
                #if os(macOS)
                // TextEditor-backed so Return inserts a newline (a vertical-axis TextField submits).
                MultilineCellEditor(
                    placeholder: String(localized: "Same as base language"),
                    text: localeTranslationBinding(state, shape: baseShape, localeCode: locale.code)
                )
                #else
                BufferedTranslationField(
                    placeholder: String(localized: "Same as base language"),
                    text: localeTranslationBinding(state, shape: baseShape, localeCode: locale.code),
                    lineLimit: 1...4
                )
                .textFieldStyle(.roundedBorder)
                #endif
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
}
