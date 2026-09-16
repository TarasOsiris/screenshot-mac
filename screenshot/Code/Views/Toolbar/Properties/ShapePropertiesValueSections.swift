import SwiftUI

/// The opacity percentage field, optionally with a slider.
struct ShapeOpacityField: View, ShapeEditing {
    let state: AppState
    let shapeId: UUID
    var showsSlider = false

    @State private var text = ""
    @State private var isActive = false

    var body: some View {
        let draft = ShapeFieldDraft(text: $text, isActive: $isActive)
        // Without a slider nothing here drags opacity, so there is no live value worth following.
        let opacity = shapeBinding(shapeId, \.opacity, continuous: showsSlider)
        HStack(spacing: 4) {
            if showsSlider {
                Slider(value: opacity, in: 0...1)
                    .frame(width: UIMetrics.SliderWidth.standard)
            }

            HStack(spacing: 0) {
                ShapePropertyField(
                    shapeId: shapeId,
                    text: $text,
                    isActive: $isActive,
                    width: propertiesOpacityFieldWidth,
                    clearsFocusOnSelectionChange: true,
                    modelValue: opacity.wrappedValue,
                    current: { currentOpacityString(for: $0) },
                    commit: { commitOpacity(to: $0, draft: draft) },
                    liveSelection: { state.selectedShapeId }
                )

                Text("%")
                    .scaledFont(UIMetrics.FontSize.numericBadge)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Rotation slider, degree field and reset.
struct ShapeRotationControl: View, ShapeEditing {
    /// `strip` is the dense bottom bar; `formRow` matches the inspector's other rows so the value
    /// fields share one column. Same split, and same reason, as `ShapeGeometryFields.Layout`.
    enum Layout { case strip, formRow }

    let state: AppState
    let shapeId: UUID
    var layout: Layout = .strip

    @State private var text = ""
    @State private var isActive = false

    var body: some View {
        let draft = ShapeFieldDraft(text: $text, isActive: $isActive)
        let slider = rotationBinding(shapeId)
        HStack(spacing: layout == .formRow ? UIMetrics.InspectorRow.columnGap : 4) {
            Slider(value: slider, in: 0...360)
                .frame(width: UIMetrics.SliderWidth.standard)

            HStack(spacing: 0) {
                ShapePropertyField(
                    shapeId: shapeId,
                    text: $text,
                    isActive: $isActive,
                    width: layout == .formRow ? UIMetrics.InspectorRow.valueWidth : propertiesNumericFieldWidth,
                    keyboard: .signed,
                    clearsFocusOnSelectionChange: true,
                    modelValue: slider.wrappedValue,
                    current: { currentRotationString(for: $0) },
                    commit: { commitRotation(to: $0, draft: draft) },
                    liveSelection: { state.selectedShapeId }
                )

                Text("°")
                    .scaledFont(UIMetrics.FontSize.numericBadge)
                    .foregroundStyle(.secondary)
            }

            if slider.wrappedValue != 0 {
                ActionButton(icon: "arrow.counterclockwise", tooltip: "Reset rotation", frameSize: UIMetrics.IconButton.frameSize) {
                    resetRotation(shapeId: shapeId, draft: draft)
                }
            }
        }
    }
}

struct ShapeCornerRadiusSection: View {
    @Binding var value: CGFloat

    var body: some View {
        ShapePropertiesSection {
            ShapePropertiesControlGroup("Radius") {
                Slider(value: $value, in: 0...500)
                    .frame(width: UIMetrics.SliderWidth.standard)

                Text(verbatim: "\(Int(value.rounded()))")
                    .scaledFont(UIMetrics.FontSize.numericBadge)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: propertiesSliderValueWidth, alignment: .trailing)
            }
        }
    }
}

struct ShapeStarPointsSection: View {
    @Binding var pointCount: Int

    var body: some View {
        ShapePropertiesSection {
            ShapePropertiesControlGroup("Points") {
                Stepper(value: $pointCount, in: 3...20) {
                    Text(verbatim: "\(pointCount)")
                        .frame(width: propertiesStepperValueWidth, alignment: .trailing)
                }
            }
        }
    }
}

struct ShapeClipToFrameSection: View {
    @Binding var clipToTemplate: Bool

    var body: some View {
        ShapePropertiesSection {
            Toggle("Clip to Frame", isOn: $clipToTemplate)
                .toggleStyle(.switch)
                .compactControlSize()
        }
    }
}

/// The abstract Android frame's camera cutout. Stored inverted (`hideCameraCutout`) so old
/// projects decode to "shown", but presented as a positive toggle.
struct AndroidCameraCutoutSection: View {
    @Binding var hideCameraCutout: Bool

    var body: some View {
        ShapePropertiesSection {
            AndroidCameraCutoutToggle(hideCameraCutout: $hideCameraCutout)
                .compactControlSize()
        }
    }
}

struct AndroidCameraCutoutToggle: View {
    @Binding var hideCameraCutout: Bool

    var body: some View {
        Toggle("Camera", isOn: Binding(
            get: { !hideCameraCutout },
            set: { hideCameraCutout = !$0 }
        ))
        .toggleStyle(.switch)
        .help("Show camera cutout on the abstract Android frame")
    }
}
