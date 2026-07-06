import SwiftUI

/// Layout constants shared by `ShapePropertiesSection` and the bars that host it.
/// Use `.horizontalPadding` on the row container so sections align flush with the bar edges.
enum ShapePropertiesSectionLayout {
    static let horizontalPadding: CGFloat = 10
    static let verticalPadding: CGFloat = 4
    static let badgeHorizontalPadding: CGFloat = 8
    static let badgeVerticalPadding: CGFloat = 4
    // Taller sections on iPad give the bottom bar's controls touch-friendly breathing room.
    // 52 = the 44pt ActionButton touch target + vertical padding, so every section in the
    // row renders at the same height regardless of which controls it holds.
    // Floor tall enough that every section's natural height (the tallest control is the ~24pt
    // fill/color swatch + vertical padding ≈ 32) is clamped to a single value, so all pills match.
    #if os(macOS)
    static let minHeight: CGFloat = 34
    #else
    static let minHeight: CGFloat = 52
    #endif
}

extension View {
    /// Accent capsule shared by the single-selection dimension badge and the multi-selection
    /// count badge so both read identically.
    func propertiesBadgeCapsule() -> some View {
        padding(.horizontal, ShapePropertiesSectionLayout.badgeHorizontalPadding)
            .padding(.vertical, ShapePropertiesSectionLayout.badgeVerticalPadding)
            .frame(minHeight: ShapePropertiesSectionLayout.minHeight)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.accentColor.opacity(UIMetrics.Opacity.accentBadge))
            )
    }

    /// Secondary "replace"-style affordance in the properties bar: dense borderless-secondary on
    /// macOS, tappable bordered on iPad. Keeps the three replace buttons identical per platform.
    @ViewBuilder
    func propertiesBarSecondaryButton() -> some View {
        #if os(macOS)
        buttonStyle(.borderless).foregroundStyle(.secondary)
        #else
        buttonStyle(.bordered)
        #endif
    }
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
        .overlay {
            RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.section, style: .continuous)
                .strokeBorder(.separator.opacity(UIMetrics.Opacity.sectionBorder), lineWidth: UIMetrics.BorderWidth.hairline)
        }
    }
}

struct ShapePropertiesSeparator: View {
    #if os(macOS)
    private static let height: CGFloat = 18
    #else
    private static let height: CGFloat = 24
    #endif

    var body: some View {
        Rectangle()
            .fill(.separator)
            .frame(width: UIMetrics.BorderWidth.standard, height: Self.height)
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

/// A popover row pairing a slider with an editable integer field. The slider drives the
/// (continuous) binding live; the field reflects it when unfocused and commits typed input
/// on submit/blur. Double-clicking the label resets to `resetValue`.
struct PopoverSliderField: View {
    let label: LocalizedStringKey
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    var resetValue: CGFloat = 0

    @State private var text = ""
    @FocusState private var focused: Bool

    private func sync() { text = "\(Int(value.rounded()))" }

    private func commit() {
        if let parsed = Double(text) {
            value = min(max(CGFloat(parsed), range.lowerBound), range.upperBound)
        }
        sync()
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: 4) {
                Slider(value: $value, in: range)
                    .frame(width: UIMetrics.SliderWidth.standard)
                TextField("", text: $text)
                    .focused($focused)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: propertiesNumericFieldWidth)
                    .integerKeyboard()
                    .onSubmit { commit() }
                    .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            }
        } label: {
            Text(label)
                .onTapGesture(count: 2) { value = resetValue }
                #if os(macOS)
                .help("Double-click to reset")
                #else
                .help("Double-tap to reset")
                #endif
        }
        .onAppear { sync() }
        .onChange(of: value) { _, _ in if !focused { sync() } }
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
        .propertiesBadgeCapsule()
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
                // Shortcut hints only make sense on macOS; on iOS they'd be read aloud by VoiceOver.
                #if os(macOS)
                ActionButton(icon: "square.3.layers.3d.top.filled", tooltip: "Bring to front (⇧⌘])", frameSize: UIMetrics.IconButton.frameSize, disabled: !canBringToFront) {
                    onBringToFront()
                }

                ActionButton(icon: "square.3.layers.3d.bottom.filled", tooltip: "Send to back (⇧⌘[)", frameSize: UIMetrics.IconButton.frameSize, disabled: !canSendToBack) {
                    onSendToBack()
                }

                ActionButton(icon: "doc.on.doc", tooltip: "Duplicate (⌘D)", frameSize: UIMetrics.IconButton.frameSize) {
                    onDuplicate()
                }

                ActionButton(icon: "trash", tooltip: "Delete (⌫)", frameSize: UIMetrics.IconButton.frameSize, isDestructive: true) {
                    onDelete()
                }
                #else
                ActionButton(icon: "square.3.layers.3d.top.filled", tooltip: "Bring to front", frameSize: UIMetrics.IconButton.frameSize, disabled: !canBringToFront) {
                    onBringToFront()
                }

                ActionButton(icon: "square.3.layers.3d.bottom.filled", tooltip: "Send to back", frameSize: UIMetrics.IconButton.frameSize, disabled: !canSendToBack) {
                    onSendToBack()
                }

                ActionButton(icon: "doc.on.doc", tooltip: "Duplicate", frameSize: UIMetrics.IconButton.frameSize) {
                    onDuplicate()
                }

                ActionButton(icon: "trash", tooltip: "Delete", frameSize: UIMetrics.IconButton.frameSize, isDestructive: true) {
                    onDelete()
                }
                #endif
            }
        }
    }
}

struct DeviceShapeControls<DevicePickerContent: View>: View {
    let shape: CanvasShapeModel
    let showsLocaleImageReset: Bool
    let onPickImage: () -> Void
    let onImageSelected: (NSImage) -> Void
    let onResetLocaleImage: () -> Void
    private let devicePickerContent: DevicePickerContent

    init(
        shape: CanvasShapeModel,
        showsLocaleImageReset: Bool,
        onPickImage: @escaping () -> Void,
        onImageSelected: @escaping (NSImage) -> Void,
        onResetLocaleImage: @escaping () -> Void,
        @ViewBuilder devicePickerContent: () -> DevicePickerContent
    ) {
        self.shape = shape
        self.showsLocaleImageReset = showsLocaleImageReset
        self.onPickImage = onPickImage
        self.onImageSelected = onImageSelected
        self.onResetLocaleImage = onResetLocaleImage
        self.devicePickerContent = devicePickerContent()
    }

    var body: some View {
        ShapePropertiesSection {
            devicePickerContent

            #if os(macOS)
            if shape.screenshotFileName != nil {
                ShapePropertiesSeparator()

                Button(action: onPickImage) {
                    Label("Replace Image", systemImage: "photo.badge.arrow.down")
                }
                .propertiesBarSecondaryButton()

                if showsLocaleImageReset {
                    ActionButton(icon: "arrow.counterclockwise", tooltip: "Reset to base-language image", frameSize: UIMetrics.IconButton.frameSize) {
                        onResetLocaleImage()
                    }
                }
            }
            #else
            ShapePropertiesSeparator()

            ImageSourceMenu(onImage: onImageSelected) {
                Label(shape.screenshotFileName == nil ? "Add Screenshot" : "Replace Image", systemImage: "photo.badge.arrow.down")
            }
            .propertiesBarSecondaryButton()

            if showsLocaleImageReset {
                ActionButton(icon: "arrow.counterclockwise", tooltip: "Reset to base-language image", frameSize: UIMetrics.IconButton.frameSize) {
                    onResetLocaleImage()
                }
            }
            #endif
        }
    }
}

struct ImageShapeControls: View {
    let buttonTitle: LocalizedStringKey
    let showsLocaleImageReset: Bool
    let onPickImage: () -> Void
    let onImageSelected: (NSImage) -> Void
    let onResetLocaleImage: () -> Void

    var body: some View {
        ShapePropertiesSection {
            #if os(macOS)
            Button(action: onPickImage) {
                Label(buttonTitle, systemImage: "photo.badge.arrow.down")
            }
            .propertiesBarSecondaryButton()
            #else
            ImageSourceMenu(onImage: onImageSelected) {
                Label(buttonTitle, systemImage: "photo.badge.arrow.down")
            }
            .propertiesBarSecondaryButton()
            #endif

            if showsLocaleImageReset {
                ActionButton(icon: "arrow.counterclockwise", tooltip: "Reset to base-language image", frameSize: UIMetrics.IconButton.frameSize) {
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
                    .compactControlSize()
                    .help("Use custom color for SVG")

                if usesCustomColor {
                    ColorPicker("SVG custom color", selection: $color, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: UIMetrics.ColorSwatch.inline)
                        .help("SVG custom color")
                }
            }

            ShapePropertiesSeparator()

            Button(action: onReplace) {
                Label("Replace SVG", systemImage: "arrow.triangle.2.circlepath")
            }
            .propertiesBarSecondaryButton()
        }
    }
}

struct FontWeightPicker: View {
    @Binding var selection: Int
    var options: [Int] = [300, 400, 500, 700]
    var width: CGFloat = 100

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
