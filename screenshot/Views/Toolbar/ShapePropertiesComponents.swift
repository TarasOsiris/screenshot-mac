import SwiftUI

struct ShapePropertiesSection<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 6) {
            content
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(minHeight: 28)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.separator.opacity(0.35), lineWidth: 0.5)
        )
    }
}

struct ShapePropertiesSeparator: View {
    var body: some View {
        Rectangle()
            .fill(.separator)
            .frame(width: 1, height: 18)
            .padding(.horizontal, 4)
    }
}

struct ShapePropertiesControlGroup<Content: View>: View {
    let label: String
    private let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
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
                .font(.system(size: 10, weight: .medium))
            Text(verbatim: "\(Int(shape.width))×\(Int(shape.height))")
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.secondary)
                .transaction { $0.animation = nil }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(Color.accentColor.opacity(0.14))
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
    let buttonTitle: String
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
                        .frame(width: 30)
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

struct TextShapeControls<TextPopoverContent: View>: View {
    let showsTranslation: Bool
    let isTranslating: Bool
    let canTranslate: Bool
    let onTranslate: () -> Void
    private let textPopoverContent: TextPopoverContent

    init(
        showsTranslation: Bool,
        isTranslating: Bool,
        canTranslate: Bool,
        onTranslate: @escaping () -> Void,
        @ViewBuilder textPopoverContent: () -> TextPopoverContent
    ) {
        self.showsTranslation = showsTranslation
        self.isTranslating = isTranslating
        self.canTranslate = canTranslate
        self.onTranslate = onTranslate
        self.textPopoverContent = textPopoverContent()
    }

    @ViewBuilder
    var body: some View {
        ShapePropertiesSection {
            textPopoverContent
        }

        if showsTranslation {
            ShapePropertiesSection {
                Button(action: onTranslate) {
                    if isTranslating {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                    } else {
                        Label("Translate", systemImage: "globe")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(isTranslating || !canTranslate)
                .help("Translate from base locale")
            }
        }
    }
}
