import SwiftUI

struct CanvasShapeInteractions {
    var onSelect: () -> Void = {}
    var onShiftSelect: (() -> Void)?
    var onUpdate: (CanvasShapeModel) -> Void = { _ in }
    var onDelete: () -> Void = {}
    var onScreenshotDrop: ((NSImage) -> Void)?
    var onClearImage: (() -> Void)?
    var onRemoveBackground: (() -> Void)?
    var onCaptureSimulator: (() -> Void)?
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
    var onMatchDeviceSizes: (() -> Void)?
    var onMatchSelectedDeviceSizes: (() -> Void)?
    var onCenterShape: ((AppState.CenterAxis) -> Void)?
    var onTranslate: (() -> Void)?
    var translateLocaleName: String?
    var onTranslateAllLocales: (() -> Void)?
    var translateAllLocalesDisabled = false
    var onResetAllTranslations: (() -> Void)?
    /// Closure, not a Bool: the answer needs an O(overrides) document walk, so
    /// it's evaluated when the context menu opens rather than on every render.
    var resetAllTranslationsDisabled: () -> Bool = { false }
    var reuseTranslationTargets: (() -> [(key: String, label: String)])?
    var onLinkTranslation: ((String) -> Void)?
    var onUnlinkTranslation: (() -> Void)?
    var nonBaseLocaleCount: Int = 0
    var onCopyTextStyle: (() -> Void)?
    var onPasteTextStyle: (() -> Void)?
    var onUpdateSelected: ((@escaping (inout CanvasShapeModel) -> Void) -> Void)?
    var onDeleteSelected: (() -> Void)?
    var onAlignSelected: ((AppState.ShapeAlignment) -> Void)?
    var onMatchGeometryToThis: ((AppState.GeometryMatchMode) -> Void)?
    var onDuplicateToTemplates: ((AppState.DuplicateDirection) -> Void)?
    var onToggleLock: (() -> Void)?
    var lockToggleWillUnlock = false
}
