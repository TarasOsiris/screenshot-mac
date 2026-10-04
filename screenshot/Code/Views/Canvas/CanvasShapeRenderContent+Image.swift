import SwiftUI
import UniformTypeIdentifiers

extension CanvasShapeRenderContent {
    @ViewBuilder
    var imageContent: some View {
        let clip = RoundedRectangle(cornerRadius: shape.borderRadius * displayScale)
        withImageDropAffordances(
            ZStack {
                if let screenshotImage {
                    let crop = clampedCrop(for: screenshotImage)
                    if isCropping {
                        // Editor-only: the part of the picture the frame hides, so a pan has a target.
                        croppedImage(screenshotImage, crop: crop)
                            .frame(width: displayW, height: displayH)
                            .saturation(UIMetrics.Opacity.cropGhostSaturation)
                            .opacity(UIMetrics.Opacity.cropGhost)
                            .allowsHitTesting(false)
                        cropPictureBounds(screenshotImage, crop: crop)
                    }
                    // Frame before clip: `.aspectRatio(.fill)` resolves to the *overflowing* size,
                    // so clipping first crops nothing and the image spills past the shape's bounds
                    // — in the editor and in every exported pixel — with the outline following it.
                    croppedImage(screenshotImage, crop: crop)
                        .frame(width: displayW, height: displayH)
                        .clipShape(clip)
                        .overlay { imageOutline(clip) }
                        .overlay {
                            if showsCropGrid {
                                CropThirdsGrid()
                            }
                        }
                } else if showsEditorHelpers {
                    // Editor-only empty state: preview and export draw nothing for an image shape
                    // with no image. Safe to branch on here — unlike `deviceContent`, neither arm
                    // holds view state that re-keying would discard.
                    clip.fill(Color.gray.opacity(0.3))
                        .overlay { imageOutline(clip) }
                }
            }
        )
    }

    /// Zoom and pan as fractions of the frame, so the crop is the same at any display scale.
    private func croppedImage(_ image: NSImage, crop: ImageCrop) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fill)
            .scaleEffect(crop.scale)
            .offset(x: crop.offsetX * displayW, y: crop.offsetY * displayH)
    }

    /// How far the window can grow: a dashed hairline around the whole picture.
    private func cropPictureBounds(_ image: NSImage, crop: ImageCrop) -> some View {
        let picture = crop.pictureRect(imageSize: image.size, frameSize: CGSize(width: displayW, height: displayH))
        return Rectangle()
            .strokeBorder(Color.accentColor.opacity(UIMetrics.Opacity.accentBorder), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .frame(width: picture.width, height: picture.height)
            .offset(x: picture.midX, y: picture.midY)
            .allowsHitTesting(false)
    }

    private func clampedCrop(for image: NSImage) -> ImageCrop {
        (imageCrop ?? ImageCrop()).clamped(imageSize: image.size, frameSize: CGSize(width: displayW, height: displayH))
    }

    /// Border drawn inside the image's rounded-rect bounds — same "band from the edge inward"
    /// behavior as `outlinedShape`, so an image outline matches a rectangle outline in parity.
    @ViewBuilder
    private func imageOutline<S: InsettableShape>(_ clip: S) -> some View {
        let inset = clampedOutlineInset
        if let outlineColor = shape.outlineColor, inset > 0 {
            clip.strokeBorder(outlineColor, lineWidth: inset)
        }
    }

    /// Makes `base` an image drop target and puts the "add image" button and drop highlight over it.
    ///
    /// Everything editor-only is an overlay or a modifier, never a branch, so `base` holds one
    /// structural position for the shape's whole lifetime. A branch here re-keys whatever `base`
    /// renders — the hazard `CanvasShapeView` states one layer up: it cost a 3D device its cached
    /// raster (and therefore its pose) the moment a picked image arrived, and `showsEditorHelpers`
    /// would have done the same on every Edit↔Preview toggle, since that is a live toggle in one
    /// tree, not a per-host constant.
    func withImageDropAffordances(_ base: some View, screenOffset: CGSize = .zero) -> some View {
        let sizeRef = min(displayW, displayH)
        let cornerRadius = min(8, max(4, sizeRef * 0.04))

        return base
            .frame(width: displayW, height: displayH)
            .overlay {
                if showsEditorHelpers, screenshotImage == nil {
                    imagePickerButton(iconSize: min(28, max(14, sizeRef * 0.18)),
                                      padding: min(12, max(4, sizeRef * 0.05)),
                                      cornerRadius: cornerRadius)
                        .offset(screenOffset)
                    // Beside the picker, never instead of it: the badge's own text says to add the
                    // image again, and on iPad there is no tooltip and no drag source to fall back
                    // on, so replacing the button leaves a broken frame with no way to fix it.
                    if resourceState != .satisfied {
                        unresolvedResourceBadge(iconSize: min(16, max(10, sizeRef * 0.1)),
                                                padding: min(6, max(3, sizeRef * 0.025)),
                                                cornerRadius: cornerRadius)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(min(8, max(3, sizeRef * 0.03)))
                    }
                }
                if showsEditorHelpers, isDropTargeted {
                    dropHighlight(cornerRadius: cornerRadius)
                }
            }
            .modifier(ImageDropTarget(isTargeted: $isDropTargeted) { providers in
                guard showsEditorHelpers else { return false }
                return onHandleDrop(providers)
            })
    }

    /// A referenced screenshot that isn't on screen is not the same as an empty frame, and the
    /// difference used to be invisible — a project whose resources hadn't synced looked finished.
    private func unresolvedResourceBadge(iconSize: CGFloat, padding: CGFloat, cornerRadius: CGFloat) -> some View {
        let isDownloading = resourceState == .downloading
        return Image(systemName: isDownloading ? "arrow.down.circle.dotted" : "exclamationmark.triangle")
            .font(.system(size: iconSize))
            .foregroundStyle(isDownloading ? Color.secondary : Color.orange)
            .padding(padding)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityLabel(isDownloading ? Text("Downloading screenshot") : Text("Screenshot file is missing"))
            .help(isDownloading
                  ? Text("This screenshot is still downloading from iCloud.")
                  : Text("This screenshot's file is missing. Add the image again to restore it."))
    }

    private func imagePickerButton(iconSize: CGFloat, padding: CGFloat, cornerRadius: CGFloat) -> some View {
        Button(action: onRequestImagePicker) {
            Image(systemName: isDropTargeted ? "arrow.down.circle.fill" : "photo.badge.plus")
                .font(.system(size: iconSize))
                .foregroundStyle(.primary)
                .padding(padding)
                .background(
                    .thinMaterial.opacity(isDropTargeted ? 0.9 : 1.0),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
        }
        .buttonStyle(EditorIconButtonStyle())
        .accessibilityLabel("Add Image")
        .help("Add Image")
        .animation(.easeInOut(duration: 0.12), value: isDropTargeted)
    }

    @ViewBuilder
    private func dropHighlight(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.accentColor.opacity(0.12))
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(Color.accentColor, lineWidth: max(2, 2 * displayScale))
    }
}

/// A raster host never receives a drop, and on macOS `.onDrop` is an AppKit-hosted view: under a
/// 45° rotation at a fractional scale its fitting frame comes out NaN and AppKit aborts in
/// `_nsis_frameInEngine` (SCREENSHOT-BRO-1Y). `isExportRendering` is fixed per host, so branching
/// on it can't re-key a live canvas the way branching on `showsEditorHelpers` would.
private struct ImageDropTarget: ViewModifier {
    @Binding var isTargeted: Bool
    let perform: ([NSItemProvider]) -> Bool
    @Environment(\.isExportRendering) private var isExportRendering

    func body(content: Content) -> some View {
        if isExportRendering {
            content
        } else {
            content.onDrop(of: [.image], isTargeted: $isTargeted, perform: perform)
        }
    }
}
