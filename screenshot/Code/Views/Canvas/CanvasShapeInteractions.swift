import SwiftUI

/// What a shape on the canvas can do to the document *while the pointer is on it* — selection,
/// dragging, dropping, inline text editing.
///
/// The context menu is deliberately not here. Its actions used to ride along as ~25 more closures
/// allocated for every shape on every row body evaluation, and the menu itself was materialized
/// into `NSMenuItem`s per shape. Both now happen once per row, at menu-open time — see
/// `EditorRowView.shapeContextMenu(for:facts:)`.
struct CanvasShapeInteractions {
    var onSelect: () -> Void = {}
    var onShiftSelect: (() -> Void)?
    var onUpdate: (CanvasShapeModel) -> Void = { _ in }
    var onScreenshotDrop: ((NSImage, ImageImportOrigin) -> Void)?
    /// Asks the row to raise its single image picker for this shape. The picker itself lives on the
    /// row: on macOS it is a `fileImporter`, i.e. a presentation host, and one per shape put a
    /// `MergePlatformItemsView` in the display list for every image and device on the canvas.
    var onRequestImagePicker: (() -> Void)?
    var onDragSnap: ((CanvasShapeModel, CGSize) -> SnapResult)?
    var onDragEnd: (() -> Void)?
    var onOptionDragDuplicate: ((UUID) -> UUID?)?
    var onDragProgress: ((CGSize) -> Void)?
    var onGroupDragEnd: ((CGSize) -> Void)?
    var onDidAppearAfterAdd: (() -> Void)?
    var onEditingTextChanged: ((Bool) -> Void)?
    var onCommitInlineText: ((_ text: String, _ richText: String?) -> Void)?
    var onInlineTextEditChanged: ((_ shapeId: UUID, _ liveText: (() -> (text: String, richText: String?))?, _ endEditing: (() -> Void)?) -> Void)?
    var onFormatBarStateChanged: ((RichTextSelectionState?, RichTextFormatController?) -> Void)?
    var onFormatBarAnchorChanged: ((CGPoint?) -> Void)?
}
