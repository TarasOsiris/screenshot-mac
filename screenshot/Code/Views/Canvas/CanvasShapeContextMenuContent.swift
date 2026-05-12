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
            if shape.type == .device {
                Menu {
                    Button("Replace Image...", systemImage: "photo") {
                        isPickerPresented = true
                    }
                    Button("Reset Image", systemImage: "arrow.counterclockwise") {
                        onClearImage?()
                    }
                    .disabled(shape.displayImageFileName == nil)
                    #if DEBUG
                    if let onCaptureSimulator {
                        Divider()
                        Button("Capture from iOS Simulator", systemImage: "iphone", action: onCaptureSimulator)
                    }
                    #endif
                } label: {
                    Label("Image", systemImage: "photo")
                }
                Divider()
            } else if shape.type == .image {
                Button("Replace Image...", systemImage: "photo") {
                    isPickerPresented = true
                }
                Button("Reset Image", systemImage: "arrow.counterclockwise") {
                    onClearImage?()
                }
                .disabled(shape.displayImageFileName == nil)
                if let screenshotImage {
                    Button("Restore Original Aspect Ratio", systemImage: "aspectratio") {
                        let imageSize = screenshotImage.size
                        guard imageSize.width > 0 && imageSize.height > 0 else { return }
                        let newHeight = shape.width / (imageSize.width / imageSize.height)
                        applyUpdate { $0.height = newHeight }
                    }
                }
                if let onRemoveBackground {
                    Button("Remove Background", systemImage: "wand.and.stars", action: onRemoveBackground)
                        .disabled(shape.displayImageFileName == nil)
                }
                Divider()
            }

            if shape.type == .device {
                Menu {
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
                } label: {
                    Label("Change Device", systemImage: "iphone")
                }
                if let onMatchDeviceSizes {
                    Button("Match Size to Other Devices", systemImage: "arrow.up.left.and.arrow.down.right", action: onMatchDeviceSizes)
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
            Toggle(isOn: Binding(
                get: { shape.italic ?? false },
                set: { value in applyUpdate { $0.italic = value } }
            )) {
                Label("Italic", systemImage: "italic")
            }
            Toggle(isOn: Binding(
                get: { shape.uppercase ?? false },
                set: { value in applyUpdate { $0.uppercase = value } }
            )) {
                Label("Uppercase", systemImage: "textformat")
            }
            Menu {
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
            } label: {
                Label("Change Font Size", systemImage: "textformat.size")
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
                Button("Translate into \(translateLocaleName)", systemImage: "character.bubble", action: onTranslate)
                    .disabled((shape.text ?? "").isEmpty)
            }
            Divider()
        }

        if shape.type == .svg {
            if let originalSize = svgOriginalSize {
                Button("Restore Original Aspect Ratio", systemImage: "aspectratio") {
                    let newHeight = shape.width / (originalSize.width / originalSize.height)
                    applyUpdate { $0.height = newHeight }
                }
            }
            Toggle(isOn: Binding(
                get: { shape.svgUseColor ?? false },
                set: { value in applyUpdate { $0.svgUseColor = value } }
            )) {
                Label("Use Custom Color", systemImage: "paintpalette")
            }
            Divider()
        }

        if shape.type == .star {
            Menu {
                ForEach(3...12, id: \.self) { count in
                    Button("\(count)") {
                        applyUpdate { $0.starPointCount = count }
                    }
                }
            } label: {
                Label("Points: \(shape.starPointCount ?? CanvasShapeModel.defaultStarPointCount)", systemImage: "star")
            }
            Divider()
        }

        Toggle(isOn: Binding(
            get: { shape.clipToTemplate ?? false },
            set: { value in applyUpdate { $0.clipToTemplate = value } }
        )) {
            Label("Clip to Frame", systemImage: "rectangle.dashed")
        }

        if let onDuplicateToTemplates {
            Menu {
                Button("To All Screenshots on the Left") {
                    onDuplicateToTemplates(.left)
                }
                Button("To All Screenshots on the Right") {
                    onDuplicateToTemplates(.right)
                }
                Button("To All Screenshots") {
                    onDuplicateToTemplates(.all)
                }
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
        }

        if let onAlignSelected {
            Divider()
            Menu {
                Button("Align Left", systemImage: "align.horizontal.left") { onAlignSelected(.left) }
                Button("Align Center", systemImage: "align.horizontal.center") { onAlignSelected(.centerH) }
                Button("Align Right", systemImage: "align.horizontal.right") { onAlignSelected(.right) }
                Divider()
                Button("Align Top", systemImage: "align.vertical.top") { onAlignSelected(.top) }
                Button("Align Middle", systemImage: "align.vertical.center") { onAlignSelected(.centerV) }
                Button("Align Bottom", systemImage: "align.vertical.bottom") { onAlignSelected(.bottom) }
                Divider()
                Button("Distribute Horizontally", systemImage: "distribute.horizontal.center") { onAlignSelected(.distributeH) }
                Button("Distribute Vertically", systemImage: "distribute.vertical.center") { onAlignSelected(.distributeV) }
            } label: {
                Label("Align Selected", systemImage: "rectangle.3.group")
            }
        }

        Divider()

        Button(isMultiSelected ? "Delete Selected" : "Delete", systemImage: "trash", role: .destructive, action: deleteAction)
    }

    private var svgOriginalSize: CGSize? {
        guard let svgContent = shape.svgContent,
              let data = svgContent.data(using: .utf8),
              let image = NSImage(data: data) else { return nil }
        return SvgHelper.parseSize(svgContent, fallbackImage: image)
    }
}
