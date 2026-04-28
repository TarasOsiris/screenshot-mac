import SwiftUI

/// Layout constants shared by `ShapePropertiesSection` and the bars that host it.
/// Use `.horizontalPadding` on the row container so sections align flush with the bar edges.
enum ShapePropertiesSectionLayout {
    static let horizontalPadding: CGFloat = 10
    static let verticalPadding: CGFloat = 4
    static let minHeight: CGFloat = 28
}

struct ShapePropertiesSection<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 6) {
            content
        }
        .padding(.horizontal, ShapePropertiesSectionLayout.horizontalPadding)
        .padding(.vertical, ShapePropertiesSectionLayout.verticalPadding)
        .frame(minHeight: ShapePropertiesSectionLayout.minHeight)
        .background(
            RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.section, style: .continuous)
                .fill(Color.primary.opacity(UIMetrics.Opacity.sectionFill))
        )
        .overlay(
            RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.section, style: .continuous)
                .strokeBorder(.separator.opacity(UIMetrics.Opacity.sectionBorder), lineWidth: UIMetrics.BorderWidth.hairline)
        )
    }
}

struct ShapePropertiesSeparator: View {
    var body: some View {
        Rectangle()
            .fill(.separator)
            .frame(width: UIMetrics.BorderWidth.standard, height: 18)
            .padding(.horizontal, 4)
    }
}

struct ShapePropertiesControlGroup<Content: View>: View {
    let label: LocalizedStringKey
    private let content: Content

    init(_ label: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(.secondary)
            content
        }
    }
}

struct ShapePropertiesBadge: View {
    let shape: CanvasShapeModel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: shape.type.icon)
                .font(.system(size: UIMetrics.FontSize.numericBadge, weight: .medium))
            Text(verbatim: "\(Int(shape.width))×\(Int(shape.height))")
                .font(.system(size: UIMetrics.FontSize.numericBadge).monospacedDigit())
                .foregroundStyle(.secondary)
                .transaction { $0.animation = nil }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(Color.accentColor.opacity(UIMetrics.Opacity.accentBadge))
        )
    }
}

struct ShapeSelectionActionsSection: View {
    let canBringToFront: Bool
    let canSendToBack: Bool
    let onBringToFront: () -> Void
    let onSendToBack: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ShapePropertiesSection {
            HStack(spacing: 4) {
                ActionButton(icon: "square.3.layers.3d.top.filled", tooltip: "Bring to front (⇧⌘])", frameSize: 24, disabled: !canBringToFront) {
                    onBringToFront()
                }

                ActionButton(icon: "square.3.layers.3d.bottom.filled", tooltip: "Send to back (⇧⌘[)", frameSize: 24, disabled: !canSendToBack) {
                    onSendToBack()
                }

                ActionButton(icon: "doc.on.doc", tooltip: "Duplicate (⌘D)", frameSize: 24) {
                    onDuplicate()
                }

                ActionButton(icon: "trash", tooltip: "Delete (⌫)", frameSize: 24, isDestructive: true) {
                    onDelete()
                }
            }
        }
    }
}

struct DeviceShapeControls<DevicePickerContent: View>: View {
    let shape: CanvasShapeModel
    let showsLocaleImageReset: Bool
    let onPickImage: () -> Void
    let onResetLocaleImage: () -> Void
    private let devicePickerContent: DevicePickerContent

    init(
        shape: CanvasShapeModel,
        showsLocaleImageReset: Bool,
        onPickImage: @escaping () -> Void,
        onResetLocaleImage: @escaping () -> Void,
        @ViewBuilder devicePickerContent: () -> DevicePickerContent
    ) {
        self.shape = shape
        self.showsLocaleImageReset = showsLocaleImageReset
        self.onPickImage = onPickImage
        self.onResetLocaleImage = onResetLocaleImage
        self.devicePickerContent = devicePickerContent()
    }

    var body: some View {
        ShapePropertiesSection {
            devicePickerContent

            if shape.screenshotFileName != nil {
                ShapePropertiesSeparator()

                Button(action: onPickImage) {
                    Label("Replace Image", systemImage: "photo.badge.arrow.down")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)

                if showsLocaleImageReset {
                    ActionButton(icon: "arrow.counterclockwise", tooltip: "Reset to default locale image", frameSize: 24) {
                        onResetLocaleImage()
                    }
                }
            }
        }
    }
}

struct ImageShapeControls: View {
    let buttonTitle: LocalizedStringKey
    let showsLocaleImageReset: Bool
    let onPickImage: () -> Void
    let onResetLocaleImage: () -> Void

    var body: some View {
        ShapePropertiesSection {
            Button(action: onPickImage) {
                Label(buttonTitle, systemImage: "photo.badge.arrow.down")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)

            if showsLocaleImageReset {
                ActionButton(icon: "arrow.counterclockwise", tooltip: "Reset to default locale image", frameSize: 24) {
                    onResetLocaleImage()
                }
            }
        }
    }
}

struct SVGShapeControls: View {
    @Binding var usesCustomColor: Bool
    @Binding var color: Color
    let onReplace: () -> Void

    var body: some View {
        ShapePropertiesSection {
            HStack(spacing: 4) {
                Toggle("Custom color", isOn: $usesCustomColor)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help("Use custom color for SVG")

                if usesCustomColor {
                    ColorPicker("", selection: $color, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: UIMetrics.ColorSwatch.inline)
                        .help("SVG custom color")
                }
            }

            ShapePropertiesSeparator()

            Button(action: onReplace) {
                Label("Replace SVG", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
    }
}

struct FontWeightPicker: View {
    @Binding var selection: Int
    var options: [Int] = [300, 400, 500, 700]
    var width: CGFloat = 90

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(options, id: \.self) { weight in
                Text(RichTextUtils.fontWeightLabel(weight)).tag(weight)
            }
        }
        .labelsHidden()
        .frame(width: width)
    }
}

struct TextShapeControls<TextPopoverContent: View>: View {
    private let textPopoverContent: TextPopoverContent

    init(@ViewBuilder textPopoverContent: () -> TextPopoverContent) {
        self.textPopoverContent = textPopoverContent()
    }

    var body: some View {
        ShapePropertiesSection {
            textPopoverContent
        }
    }
}
