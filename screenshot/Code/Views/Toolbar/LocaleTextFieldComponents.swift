import SwiftUI

/// Buffers edits locally so binding straight to @Observable AppState doesn't reset the
/// caret on every keystroke (the body recomputes and re-feeds the value otherwise).
struct BufferedTranslationField: View {
    let placeholder: String
    @Binding var text: String
    @State private var localText: String
    @FocusState private var isFocused: Bool

    init(placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        self._text = text
        self._localText = State(initialValue: text.wrappedValue)
    }

    var body: some View {
        TextField(placeholder, text: $localText, axis: .vertical)
            .lineLimit(1...6)
            .focused($isFocused)
            .debouncedFieldCommit(buffer: $localText, into: $text, isFocused: isFocused)
    }
}

/// Commits a cell's local editing buffer into its `@Observable`-backed binding on a debounce, and
/// flushes immediately when the cell disappears (sheet dismiss, List/LazyVStack recycling). Writing
/// the model on every keystroke would mutate `localeState`/`rows` and rebuild the entire grid per
/// keystroke; debouncing means only the focused cell re-renders while typing.
struct DebouncedFieldCommit: ViewModifier {
    @Binding var buffer: String
    @Binding var committed: String
    var isFocused: Bool
    var delay: TimeInterval = 0.3
    @State private var commitTask: DispatchWorkItem?

    func body(content: Content) -> some View {
        content
            .onChange(of: buffer) { _, newValue in
                commitTask?.cancel()
                let task = DispatchWorkItem { if newValue != committed { committed = newValue } }
                commitTask = task
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
            }
            .onChange(of: committed) { _, newValue in
                // An external write (Translate, auto-translate, locale switch) supersedes any in-flight
                // buffer commit — cancel it so a stale debounce can't revert the new value.
                guard newValue != buffer else { return }
                commitTask?.cancel()
                commitTask = nil
                buffer = newValue
            }
            .onChange(of: isFocused) { _, focused in
                // Commit immediately on blur so leaving the cell (e.g. to click Translate) flushes
                // the latest text, and nothing is left pending past the edit.
                if !focused { flush() }
            }
            .onDisappear { flush() }
    }

    private func flush() {
        commitTask?.cancel()
        commitTask = nil
        if buffer != committed { committed = buffer }
    }
}

extension View {
    func debouncedFieldCommit(buffer: Binding<String>, into committed: Binding<String>, isFocused: Bool) -> some View {
        modifier(DebouncedFieldCommit(buffer: buffer, committed: committed, isFocused: isFocused))
    }
}

/// Plain text of a *formatted* translation override, or nil when it carries no rich text.
/// Rich-text translations are shown read-only — a plain field can't edit formatting and the
/// `richText` override wins at render time anyway.
func formattedTranslationPlainText(for override: ShapeLocaleOverride?) -> String? {
    guard let override, let richText = override.richText, !richText.isEmpty else { return nil }
    // Prefer the stored plain-text mirror; only decode the RTF when there isn't one.
    return override.text ?? RichTextUtils.plainText(from: richText) ?? ""
}

/// Override text binding for one locale; a blank value resets to the base language. Reads/writes
/// through the shape's (possibly shared) translation key, so reused strings stay in sync.
func localeTranslationBinding(_ state: AppState, shape: CanvasShapeModel, localeCode: String) -> Binding<String> {
    Binding(
        get: { state.translationOverrideForDisplay(shape: shape, localeCode: localeCode)?.text ?? "" },
        set: { newValue in
            if isUntranslated(newValue) {
                state.resetTranslationText(shapeId: shape.id, localeCode: localeCode)
            } else {
                state.updateTranslationText(shapeId: shape.id, localeCode: localeCode, text: newValue)
            }
        }
    )
}

/// Shared "Reuse Translation" pull-down: link this text to another string (sharing base text + all
/// translations) or stop reusing. Used by both the canvas context menu and the localization popover.
/// `targets` is a closure so the full (possibly large) target list is built only when the menu opens.
@ViewBuilder
func reuseTranslationMenuContent(
    isLinked: Bool,
    hasTargets: Bool,
    targets: @escaping () -> [(key: String, label: String)],
    onLink: @escaping (String) -> Void,
    onUnlink: (() -> Void)? = nil
) -> some View {
    if isLinked || hasTargets {
        Menu {
            if isLinked, let onUnlink {
                Button("Stop Reusing Translation", systemImage: "link.badge.minus", action: onUnlink)
                if hasTargets { Divider() }
            }
            if hasTargets {
                Section("Reuse translation from") {
                    ForEach(targets(), id: \.key) { target in
                        Button(target.label) { onLink(target.key) }
                    }
                }
            }
        } label: {
            Label("Reuse Translation", systemImage: "link")
        }
    }
}

#if os(macOS)
/// Multiline editor that uses `TextEditor` so Return inserts a newline (a
/// vertical-axis `TextField` treats Return as a submit gesture on macOS).
struct MultilineCellEditor: View {
    let placeholder: String
    @Binding var text: String
    var help: String? = nil
    var autofocus: Bool = false
    var onEditingEnded: (() -> Void)? = nil

    // Local buffer: binding TextEditor straight to AppState-backed state recomputes
    // the body on every keystroke and re-feeds the value, resetting the caret to the
    // end. The buffer survives recomputes; we sync to/from `text` only on real changes.
    @State private var localText: String
    @FocusState private var isFocused: Bool

    init(
        placeholder: String,
        text: Binding<String>,
        help: String? = nil,
        autofocus: Bool = false,
        onEditingEnded: (() -> Void)? = nil
    ) {
        self.placeholder = placeholder
        self._text = text
        self.help = help
        self.autofocus = autofocus
        self.onEditingEnded = onEditingEnded
        self._localText = State(initialValue: text.wrappedValue)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if localText.isEmpty {
                Text(placeholder)
                    .font(.system(size: CellEditorStyle.fontSize))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, CellEditorStyle.insetH)
                    .padding(.vertical, CellEditorStyle.insetV)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $localText)
                .font(.system(size: CellEditorStyle.fontSize))
                .scrollContentBackground(.hidden)
                .focused($isFocused)
        }
        .cellEditorHeight(measuring: localText.isEmpty ? placeholder : localText)
        .debouncedFieldCommit(buffer: $localText, into: $text, isFocused: isFocused)
        .cellEditorChrome()
        .modifier(OptionalHelp(help: help))
        // Defer one tick: setting focus before the view is in a window can be dropped.
        .onAppear { if autofocus { Task { @MainActor in isFocused = true } } }
        .onChange(of: isFocused) { _, focused in if !focused { onEditingEnded?() } }
    }
}

/// Shared geometry/visual tokens for the matrix cell editor and its read-only preview,
/// so swapping one for the other never shifts a cell's size or chrome.
enum CellEditorStyle {
    static let fontSize: CGFloat = 12
    // Match the TextEditor's intrinsic text origin so the placeholder/mirror align.
    static let insetH: CGFloat = 5
    static let insetV: CGFloat = 5
    static let minHeight: CGFloat = 40   // ~2 lines
    static let maxHeight: CGFloat = 100  // ~6 lines

    static func clampHeight(_ height: CGFloat) -> CGFloat {
        min(max(height, minHeight), maxHeight)
    }
}

extension View {
    /// Shared cell-editor box chrome (fill + hairline border + clip) so the live editor,
    /// the read-only preview, and the formatted cell stay pixel-identical.
    func cellEditorChrome() -> some View {
        background(Color.platformTextBackground)
            .overlay(
                RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.card)
                    .stroke(Color.platformSeparator, lineWidth: UIMetrics.BorderWidth.standard)
            )
            .clipShape(RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.card))
    }
}

extension View {
    /// Sizes a cell to fit `text` at the editor's font/insets, clamped to the shared
    /// min/max, so the live editor and the read-only preview measure identically and the
    /// row never jumps height when one swaps for the other.
    func cellEditorHeight(measuring text: String) -> some View {
        modifier(CellEditorHeight(measuredText: text))
    }
}

private struct CellEditorHeight: ViewModifier {
    let measuredText: String
    @State private var contentHeight: CGFloat = 0

    func body(content: Content) -> some View {
        ZStack(alignment: .topLeading) {
            // Invisible mirror reports the text's natural height via `CellHeightKey`.
            Text(measuredText)
                .font(.system(size: CellEditorStyle.fontSize))
                .padding(.horizontal, CellEditorStyle.insetH)
                .padding(.vertical, CellEditorStyle.insetV)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: CellHeightKey.self, value: proxy.size.height)
                })
                .hidden()

            content
        }
        .frame(height: CellEditorStyle.clampHeight(contentHeight))
        .onPreferenceChange(CellHeightKey.self) { contentHeight = $0 }
    }
}

/// Cheap, read-only stand-in for `MultilineCellEditor`, shown while a cell isn't being
/// edited so a large translation matrix doesn't mount one live `TextEditor` per cell.
/// Matches the editor's font, insets, height clamp, and chrome.
struct MatrixCellPreview: View {
    let text: String
    let placeholder: String
    var help: String? = nil

    var body: some View {
        let isEmpty = text.isEmpty
        Text(isEmpty ? placeholder : text)
            .font(.system(size: CellEditorStyle.fontSize))
            .foregroundStyle(isEmpty ? .tertiary : .primary)
            .padding(.horizontal, CellEditorStyle.insetH)
            .padding(.vertical, CellEditorStyle.insetV)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .allowsHitTesting(false)
            .cellEditorHeight(measuring: isEmpty ? placeholder : text)
            .cellEditorChrome()
            .contentShape(Rectangle())
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
