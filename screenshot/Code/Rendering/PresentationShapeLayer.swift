import SwiftUI

extension CanvasShapeView {
    /// The non-interactive configuration shared by export, the single-template renderer, the row
    /// preview tile and the parity tests. Editor-only inputs (selection, drag session, helpers,
    /// interactions) are off by construction, so these paths cannot drift apart the way four
    /// hand-written argument lists did.
    ///
    /// `defaultDeviceBodyColor` is passed rather than read off a row because the single-template
    /// renderer lays shapes out against a synthesized one-template row while the colour must
    /// still come from the real one.
    static func presentation(
        shape: CanvasShapeModel,
        images: [String: NSImage],
        displayScale: CGFloat,
        defaultDeviceBodyColor: Color,
        availableFontFamilies: Set<String>,
        clipBounds: CGRect?,
        allowSynchronousSvgRender: Bool = true,
        showsEditorHelpers: Bool = false
    ) -> CanvasShapeView {
        CanvasShapeView(
            shape: shape,
            displayScale: displayScale,
            zoom: 1.0,
            isSelected: false,
            screenshotImage: shape.displayImageFileName.flatMap { images[$0] },
            screenshotImageIdentity: shape.displayImageFileName,
            fillImage: shape.fillImageConfig?.fileName.flatMap { images[$0] },
            defaultDeviceBodyColor: defaultDeviceBodyColor,
            deviceModelRenderingMode: .snapshot,
            clipBounds: clipBounds,
            showsEditorHelpers: showsEditorHelpers,
            allowSynchronousSvgRender: allowSynchronousSvgRender,
            availableFontFamilies: availableFontFamilies
        )
    }
}

/// A row's shape layer as every non-editor path builds it. The editor keeps its own
/// construction — it needs the drag session and the interaction closures.
struct PresentationShapeLayerView: View {
    let row: ScreenshotRow
    let shapes: [CanvasShapeModel]
    let images: [String: NSImage]
    let displayScale: CGFloat
    let defaultDeviceBodyColor: Color
    let availableFontFamilies: Set<String>
    var allowSynchronousSvgRender = true
    var showsEditorHelpers = false

    var body: some View {
        RowCanvasShapeLayerView(row: row, shapes: shapes, displayScale: displayScale) { shape, clipRect in
            CanvasShapeView.presentation(
                shape: shape,
                images: images,
                displayScale: displayScale,
                defaultDeviceBodyColor: defaultDeviceBodyColor,
                availableFontFamilies: availableFontFamilies,
                clipBounds: clipRect,
                allowSynchronousSvgRender: allowSynchronousSvgRender,
                showsEditorHelpers: showsEditorHelpers
            )
        }
    }
}
