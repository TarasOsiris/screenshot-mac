import SwiftUI
import AppKit

enum RichTextFormatBarMetrics {
    static let width: CGFloat = 372
    static let height: CGFloat = 42
    static let controlSize = CGSize(width: 28, height: 28)
    static let cornerRadius: CGFloat = UIMetrics.CornerRadius.floating
    static let edgeInset: CGFloat = 4
}

/// Derived selection state for the format bar, avoiding [Key: Any] dictionary which isn't Equatable.
struct RichTextSelectionState: Equatable {
    var isBold: Bool = false
    var isItalic: Bool = false
    var isUnderline: Bool = false
    var isStrikethrough: Bool = false
    var fontSize: CGFloat = 72
    var color: CodableColor = CodableColor(.white)
    var hasRangeSelection: Bool = false

    init() {}

    init(from attributes: [NSAttributedString.Key: Any]?, hasRangeSelection: Bool) {
        self.hasRangeSelection = hasRangeSelection
        guard let attributes else { return }
        if let font = attributes[.font] as? NSFont {
            isBold = font.fontDescriptor.symbolicTraits.contains(.bold)
            isItalic = font.fontDescriptor.symbolicTraits.contains(.italic)
            fontSize = font.pointSize
        }
        if let style = attributes[.underlineStyle] as? Int { isUnderline = style != 0 }
        if let style = attributes[.strikethroughStyle] as? Int { isStrikethrough = style != 0 }
        if let nsColor = attributes[.foregroundColor] as? NSColor { color = CodableColor(Color(nsColor)) }
    }
}

/// Floating toolbar for applying per-range text formatting.
struct RichTextFormatBar: View {
    var selectionState: RichTextSelectionState
    var onApplyFormat: (RichTextFormatAction) -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                formatButton(systemName: "bold", isActive: selectionState.isBold, helpText: "Toggle bold") {
                    onApplyFormat(.toggleBold)
                }
                formatButton(systemName: "italic", isActive: selectionState.isItalic, helpText: "Toggle italic") {
                    onApplyFormat(.toggleItalic)
                }
                formatButton(systemName: "underline", isActive: selectionState.isUnderline, helpText: "Toggle underline") {
                    onApplyFormat(.toggleUnderline)
                }
                formatButton(systemName: "strikethrough", isActive: selectionState.isStrikethrough, helpText: "Toggle strikethrough") {
                    onApplyFormat(.toggleStrikethrough)
                }
            }

            divider

            HStack(spacing: 4) {
                stepButton(systemName: "minus", helpText: "Decrease font size") {
                    onApplyFormat(.setFontSize(max(8, selectionState.fontSize - 2)))
                }
                Menu {
                    ForEach(CanvasShapeModel.fontSizePresets, id: \.self) { size in
                        Button("\(size) pt") {
                            onApplyFormat(.setFontSize(CGFloat(size)))
                        }
                    }
                } label: {
                    Text("\(Int(selectionState.fontSize.rounded()))")
                        .font(.system(size: UIMetrics.FontSize.body, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.primary)
                        .frame(width: 42, height: RichTextFormatBarMetrics.controlSize.height)
                        .background(
                            RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.section)
                                .fill(Color.primary.opacity(UIMetrics.Opacity.sectionFill))
                        )
                }
                .menuStyle(.borderlessButton)
                .help("Font size")

                stepButton(systemName: "plus", helpText: "Increase font size") {
                    onApplyFormat(.setFontSize(min(400, selectionState.fontSize + 2)))
                }
            }

            divider

            ColorPicker("", selection: Binding(
                get: { selectionState.color.color },
                set: { onApplyFormat(.setColor($0)) }
            ), supportsOpacity: false)
            .labelsHidden()
            .frame(width: RichTextFormatBarMetrics.controlSize.width, height: RichTextFormatBarMetrics.controlSize.height)
            .padding(.horizontal, 4)
            .help("Text color")

            divider

            formatButton(systemName: "eraser", isActive: false, helpText: "Clear formatting") {
                onApplyFormat(.clearFormatting)
            }
        }
        .padding(6)
        .frame(width: RichTextFormatBarMetrics.width, height: RichTextFormatBarMetrics.height)
        .background {
            RoundedRectangle(cornerRadius: RichTextFormatBarMetrics.cornerRadius)
                .fill(.ultraThickMaterial)
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: RichTextFormatBarMetrics.cornerRadius)
                .strokeBorder(UIMetrics.Stroke.subtle, lineWidth: UIMetrics.BorderWidth.standard)
        }
    }

    private var divider: some View {
        Divider()
            .frame(height: 20)
    }

    private func stepButton(systemName: String, helpText: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: UIMetrics.FontSize.numericBadge, weight: .semibold))
                .frame(width: RichTextFormatBarMetrics.controlSize.width, height: RichTextFormatBarMetrics.controlSize.height)
        }
        .buttonStyle(FormatBarButtonStyle(isActive: false))
        .help(helpText)
    }

    private func formatButton(systemName: String, isActive: Bool, helpText: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: UIMetrics.FontSize.body, weight: .semibold))
                .frame(width: RichTextFormatBarMetrics.controlSize.width, height: RichTextFormatBarMetrics.controlSize.height)
        }
        .buttonStyle(FormatBarButtonStyle(isActive: isActive))
        .help(helpText)
    }
}

private struct FormatBarButtonStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isActive ? Color.accentColor : .primary)
            .background(
                RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.section)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.section)
                    .strokeBorder(borderColor(isPressed: configuration.isPressed), lineWidth: UIMetrics.BorderWidth.standard)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isPressed {
            return Color.accentColor.opacity(UIMetrics.Opacity.accentPressed)
        }
        if isActive {
            return Color.accentColor.opacity(UIMetrics.Opacity.accentBadge)
        }
        return Color.primary.opacity(UIMetrics.Opacity.sectionFill)
    }

    private func borderColor(isPressed: Bool) -> Color {
        if isPressed || isActive {
            return Color.accentColor.opacity(UIMetrics.Opacity.accentBorder)
        }
        return Color.primary.opacity(UIMetrics.Opacity.hairlineOverlay)
    }
}

enum RichTextFormatAction {
    case toggleBold
    case toggleItalic
    case toggleUnderline
    case toggleStrikethrough
    case setFontSize(CGFloat)
    case setColor(Color)
    case clearFormatting
}
