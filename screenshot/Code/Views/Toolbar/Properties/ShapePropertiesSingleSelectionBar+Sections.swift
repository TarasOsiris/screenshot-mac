import SwiftUI

// The per-shape-type runs of the properties bar, lifted out of `body` so the bar reads as
// the ordered list of sections it is. They stay methods on the bar rather than standalone
// views because every one of them needs the binding factories in `+ValueBindings`.
extension ShapePropertiesSingleSelectionBar {
    @ViewBuilder
    func deviceSections(shape: CanvasShapeModel, shapeId: UUID) -> some View {
        if shape.type == .device {
            DeviceShapeControls(
                shape: shape,
                showsLocaleImageReset: hasLocaleImageOverride(shapeId),
                onPickImage: { pickAndReplaceImage(for: shapeId) },
                onImageSelected: { state.saveImage($0, for: shapeId) },
                onResetLocaleImage: { state.resetLocaleImageOverride(shapeId: shapeId) }
            ) {
                devicePicker(shape: shape, shapeId: shapeId)
            }
        }

        if shape.type == .device
            && shape.deviceCategory == .androidPhone
            && shape.deviceFrameId == nil {
            AndroidCameraCutoutSection(
                hideCameraCutout: shapeBinding(shapeId, \.hideCameraCutout, default: false)
            )
        }

        if shape.supportsDeviceModelRotation {
            ShapeDeviceModelRotationControls(
                pitch: deviceModelRotationBinding(shapeId, \.devicePitch, defaultValue: \.resolvedDevicePitch),
                yaw: deviceModelRotationBinding(shapeId, \.deviceYaw, defaultValue: \.resolvedDeviceYaw),
                canReset: hasDeviceModelRotationOverride(shapeId),
                onReset: { resetDeviceModelRotation(shapeId) },
                bodyMaterial: optionalConfigBinding(shapeId, \.deviceBodyMaterial, fallback: DeviceBodyMaterial(), isEmpty: \.isEmpty),
                lighting: optionalConfigBinding(shapeId, \.deviceLighting, fallback: DeviceLighting(), isEmpty: \.isEmpty)
            )
        }
    }

    @ViewBuilder
    func fillSection(shape: CanvasShapeModel, shapeId: UUID) -> some View {
        if shape.type.supportsFill {
            ShapePropertiesSection {
                ShapeFillSwatchButton(
                    shape: shape,
                    isPresented: $isFillPopoverPresented,
                    backgroundStyle: fillStyleBinding(shapeId),
                    bgColor: shapeBinding(shapeId, \.color),
                    gradientConfig: shapeBinding(shapeId, \.fillGradientConfig, default: GradientConfig(), continuous: true),
                    backgroundImageConfig: shapeBinding(shapeId, \.fillImageConfig, default: BackgroundImageConfig(), continuous: true),
                    backgroundImage: {
                        (idx(for: shapeId).flatMap { i in
                            state.rows[i.row].shapes[i.shape].fillImageConfig?.fileName
                        }).flatMap { state.screenshotImages[$0] }
                    },
                    onChanged: { state.scheduleSave() },
                    // macOS opens a file panel here; iPad picks via ImageSourceMenu
                    // inside BackgroundImageEditor (→ onDropImage → saveShapeFillImage).
                    onPickImage: {
                        #if os(macOS)
                        isReplacingFillImage = true
                        #endif
                    },
                    onRemoveImage: { state.removeShapeFillImage(for: shapeId) },
                    onDropImage: { image in state.saveShapeFillImage(image, for: shapeId) }
                )
            }
        } else if shape.type != .device && shape.type != .svg && shape.type != .image {
            ShapePropertiesSection {
                ColorPicker("Fill color", selection: shapeBinding(shapeId, \.color), supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: UIMetrics.ColorSwatch.inline)
                    .help("Fill color")
            }
        }
    }

    @ViewBuilder
    func shapeGeometrySections(shape: CanvasShapeModel, shapeId: UUID) -> some View {
        if shape.type == .rectangle || shape.type == .image || (shape.type == .device && shape.deviceCategory == .invisible) {
            ShapeCornerRadiusSection(
                value: shapeBinding(shapeId, \.borderRadius, continuous: true)
            )
        }

        if shape.type.supportsOutline || (shape.type == .device && shape.deviceCategory == .invisible) {
            ShapePropertiesSection {
                ShapeOutlineControls(
                    shape: shape,
                    hasOutline: outlineEnabledBinding(shape),
                    outlineColor: shapeBinding(shapeId, \.outlineColor, default: CanvasShapeModel.defaultOutlineColor),
                    outlineWidth: shapeBinding(shapeId, \.outlineWidth, default: CanvasShapeModel.defaultOutlineWidth, continuous: true)
                )
            }
        }

        if shape.type == .star {
            ShapeStarPointsSection(
                pointCount: shapeBinding(shapeId, \.starPointCount, default: CanvasShapeModel.defaultStarPointCount)
            )
        }
    }

    @ViewBuilder
    func mediaSections(shape: CanvasShapeModel, shapeId: UUID) -> some View {
        if shape.type == .image {
            ImageShapeControls(
                buttonTitle: shape.imageFileName != nil ? "Replace Image" : "Choose Image",
                showsLocaleImageReset: hasLocaleImageOverride(shapeId),
                onPickImage: { pickAndReplaceImage(for: shapeId) },
                onImageSelected: { state.saveImage($0, for: shapeId) },
                onResetLocaleImage: { state.resetLocaleImageOverride(shapeId: shapeId) }
            )
        }

        if shape.type == .svg {
            SVGShapeControls(
                usesCustomColor: shapeBinding(shapeId, \.svgUseColor, default: false),
                color: shapeBinding(shapeId, \.color),
                onReplace: { isReplacingSvg = true }
            )
        }
    }

    @ViewBuilder
    func textSections(shape: CanvasShapeModel, shapeId: UUID) -> some View {
        if shape.type == .text {
            TextShapeControls {
                textPopoverButton(shape: shape, shapeId: shapeId)
            }
            ShapePropertiesSection {
                textBackgroundButton(shape: shape, shapeId: shapeId)
            }
            if state.localeState.nonBaseLocaleCount > 0 {
                ShapePropertiesSection {
                    textLocalizationButton(shape: shape, shapeId: shapeId)
                }
            }
        }
    }
}
