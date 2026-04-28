import SwiftUI

struct CanvasShapeContextMenuContent: View {
    let shape: CanvasShapeModel
    var isMultiSelected: Bool = false
    var screenshotImage: NSImage?
    @Binding var isPickerPresented: Bool
    var onClearImage: (() -> Void)?
    var onRemoveBackground: (() -> Void)?
    var onCaptureSimulator: (() -> Void)?
    var onMatchDeviceSizes: (() -> Void)?
    var onTranslate: (() -> Void)?
    var translateLocaleName: String?
    var onCopyTextStyle: (() -> Void)?
    var onPasteTextStyle: (() -> Void)?
    let applyUpdate: (@escaping (inout CanvasShapeModel) -> Void) -> Void
    let deleteAction: () -> Void
    var onAlignSelected: ((AppState.ShapeAlignment) -> Void)?
    var onDuplicateToTemplates: ((AppState.DuplicateDirection) -> Void)?

    var body: some View {
        if !isMultiSelected {
            if shape.type == .device || shape.type == .image {
                Button("Replace Image...") {
                    isPickerPresented = true
                }
                if shape.type == .device, let onCaptureSimulator {
                    Button("Capture from iOS Simulator", action: onCaptureSimulator)
                }
                Button("Reset Image") {
                    onClearImage?()
                }
                .disabled(shape.displayImageFileName == nil)
                if shape.type == .image, let screenshotImage {
                    Button("Restore Original Aspect Ratio") {
                        let imageSize = screenshotImage.size
                        guard imageSize.width > 0 && imageSize.height > 0 else { return }
                        let newHeight = shape.width / (imageSize.width / imageSize.height)
                        applyUpdate { $0.height = newHeight }
                    }
                }
                if shape.type == .image, let onRemoveBackground {
                    Button("Remove Background", action: onRemoveBackground)
                        .disabled(shape.displayImageFileName == nil)
                }
                Divider()
            }

            if shape.type == .device {
                Menu("Change Device") {
                    DeviceMenuContent(
                        onSelectCategory: { category in
                            applyUpdate { $0.selectAbstractDevice(category, screenshotImageSize: screenshotImage?.size) }
                        },
                        onSelectFrame: { frame in
                            applyUpdate { $0.selectRealFrame(frame) }
                        },
                        selectedCategory: shape.deviceCategory,
                        selectedFrameId: shape.deviceFrameId
                    )
                }
                if let onMatchDeviceSizes {
                    Button("Match Size to Other Devices", action: onMatchDeviceSizes)
                }
                Divider()
            }
        }

        if shape.type == .text {
            Picker("Align", selection: Binding(
                get: { shape.textAlign ?? .center },
                set: { value in applyUpdate { $0.textAlign = value } }
            )) {
                Label("Left", systemImage: "text.alignleft").tag(TextAlign.left)
                Label("Center", systemImage: "text.aligncenter").tag(TextAlign.center)
                Label("Right", systemImage: "text.alignright").tag(TextAlign.right)
            }
            Toggle("Italic", isOn: Binding(
                get: { shape.italic ?? false },
                set: { value in applyUpdate { $0.italic = value } }
            ))
            Toggle("Uppercase", isOn: Binding(
                get: { shape.uppercase ?? false },
                set: { value in applyUpdate { $0.uppercase = value } }
            ))
            Menu("Change Font Size") {
                let currentSize = Int(shape.fontSize ?? CanvasShapeModel.defaultFontSize)
                ForEach(CanvasShapeModel.fontSizePresets, id: \.self) { size in
                    Button {
                        applyUpdate { $0.fontSize = CGFloat(size) }
                    } label: {
                        if currentSize == size {
                            Label("\(size)", systemImage: "checkmark")
                        } else {
                            Text("\(size)")
                        }
                    }
                }
            }
            if !isMultiSelected, let onCopyTextStyle {
                Divider()
                Button("Copy Text Style", systemImage: "paintbrush") {
                    onCopyTextStyle()
                }
                Button("Paste Text Style", systemImage: "paintbrush.fill") {
                    onPasteTextStyle?()
                }
                .disabled(onPasteTextStyle == nil)
            }
            if !isMultiSelected, let onTranslate, let translateLocaleName {
                Divider()
                Button("Translate into \(translateLocaleName)", action: onTranslate)
                    .disabled((shape.text ?? "").isEmpty)
            }
            Divider()
        }

        if shape.type == .svg {
            if let originalSize = svgOriginalSize {
                Button("Restore Original Aspect Ratio") {
                    let newHeight = shape.width / (originalSize.width / originalSize.height)
                    applyUpdate { $0.height = newHeight }
                }
            }
            Toggle("Use Custom Color", isOn: Binding(
                get: { shape.svgUseColor ?? false },
                set: { value in applyUpdate { $0.svgUseColor = value } }
            ))
            Divider()
        }

        if shape.type == .star {
            Menu("Points: \(shape.starPointCount ?? CanvasShapeModel.defaultStarPointCount)") {
                ForEach(3...12, id: \.self) { count in
                    Button("\(count)") {
                        applyUpdate { $0.starPointCount = count }
                    }
                }
            }
            Divider()
        }

        Toggle("Clip to Frame", isOn: Binding(
            get: { shape.clipToTemplate ?? false },
            set: { value in applyUpdate { $0.clipToTemplate = value } }
        ))

        if let onDuplicateToTemplates {
            Menu("Duplicate") {
                Button("To All Screenshots on the Left") {
                    onDuplicateToTemplates(.left)
                }
                Button("To All Screenshots on the Right") {
                    onDuplicateToTemplates(.right)
                }
                Button("To All Screenshots") {
                    onDuplicateToTemplates(.all)
                }
            }
        }

        if let onAlignSelected {
            Divider()
            Menu("Align Selected") {
                Button("Align Left") { onAlignSelected(.left) }
                Button("Align Center") { onAlignSelected(.centerH) }
                Button("Align Right") { onAlignSelected(.right) }
                Divider()
                Button("Align Top") { onAlignSelected(.top) }
                Button("Align Middle") { onAlignSelected(.centerV) }
                Button("Align Bottom") { onAlignSelected(.bottom) }
                Divider()
                Button("Distribute Horizontally") { onAlignSelected(.distributeH) }
                Button("Distribute Vertically") { onAlignSelected(.distributeV) }
            }
        }

        Divider()

        Button(isMultiSelected ? "Delete Selected" : "Delete", role: .destructive, action: deleteAction)
    }

    private var svgOriginalSize: CGSize? {
        guard let svgContent = shape.svgContent,
              let data = svgContent.data(using: .utf8),
              let image = NSImage(data: data) else { return nil }
        return SvgHelper.parseSize(svgContent, fallbackImage: image)
    }
}
