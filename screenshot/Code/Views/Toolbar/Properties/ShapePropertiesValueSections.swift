import SwiftUI

struct ShapeOpacitySection: View {
    let shapeId: UUID
    let field: ShapePropertiesSingleSelectionBar.Field
    let opacity: Double
    @Binding var text: String
    @Binding var isActive: Bool
    var focus: FocusState<ShapePropertiesSingleSelectionBar.Field?>.Binding
    let current: (UUID) -> String
    let commit: (UUID?) -> Void
    let liveSelection: () -> UUID?

    var body: some View {
        ShapePropertiesSection {
            ShapePropertiesControlGroup("Opacity") {
                HStack(spacing: 0) {
                    ShapePropertyField(
                        shapeId: shapeId,
                        field: field,
                        text: $text,
                        isActive: $isActive,
                        focus: focus,
                        width: propertiesOpacityFieldWidth,
                        clearsFocusOnSelectionChange: true,
                        modelValue: opacity,
                        current: current,
                        commit: commit,
                        liveSelection: liveSelection
                    )

                    Text("%")
                        .scaledFont(UIMetrics.FontSize.numericBadge)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct ShapeRotationSection: View {
    let shapeId: UUID
    let field: ShapePropertiesSingleSelectionBar.Field
    @Binding var slider: Double
    @Binding var text: String
    @Binding var isActive: Bool
    var focus: FocusState<ShapePropertiesSingleSelectionBar.Field?>.Binding
    let current: (UUID) -> String
    let commit: (UUID?) -> Void
    let liveSelection: () -> UUID?
    let onReset: () -> Void

    var body: some View {
        ShapePropertiesSection {
            ShapePropertiesControlGroup("Rotation") {
                Slider(value: $slider, in: 0...360)
                    .frame(width: UIMetrics.SliderWidth.standard)

                HStack(spacing: 0) {
                    ShapePropertyField(
                        shapeId: shapeId,
                        field: field,
                        text: $text,
                        isActive: $isActive,
                        focus: focus,
                        width: propertiesNumericFieldWidth,
                        keyboard: .signed,
                        clearsFocusOnSelectionChange: true,
                        modelValue: slider,
                        current: current,
                        commit: commit,
                        liveSelection: liveSelection
                    )

                    Text("°")
                        .scaledFont(UIMetrics.FontSize.numericBadge)
                        .foregroundStyle(.secondary)
                }

                if slider != 0 {
                    ActionButton(icon: "arrow.counterclockwise", tooltip: "Reset rotation", frameSize: UIMetrics.IconButton.frameSize, action: onReset)
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
            Toggle("Camera", isOn: Binding(
                get: { !hideCameraCutout },
                set: { hideCameraCutout = !$0 }
            ))
            .toggleStyle(.switch)
            .compactControlSize()
            .help("Show camera cutout on the abstract Android frame")
        }
    }
}
