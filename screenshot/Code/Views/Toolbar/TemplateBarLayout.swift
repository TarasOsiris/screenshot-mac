import CoreGraphics

/// Which buttons a `TemplateControlBar` keeps as its column narrows.
///
/// The bar is pinned to the (zoom-scaled) column width, so at low zoom it gets narrower than its
/// own buttons — especially with the larger iPad touch targets.
nonisolated enum TemplateBarLayout {
    enum Button: CaseIterable {
        case more, preview, download, moveLeft, moveRight, background, delete
    }

    /// Kept longest first. `more` and `delete` are the bar's fixed trailing pair, so they anchor
    /// the list; of the rest, `background` outlives them because it is the only control the
    /// ellipsis menu does not also offer, and `download` goes first because it does.
    private static let priority: [Button] = [.more, .delete, .background, .preview, .moveLeft, .moveRight, .download]

    static func visibleButtons(
        availableWidth: CGFloat,
        buttonWidth: CGFloat,
        spacing: CGFloat,
        canDelete: Bool
    ) -> Set<Button> {
        // However narrow the column gets, the ellipsis menu stays — it is the only way to reach
        // everything the bar has dropped.
        let slots = max(1, Int((availableWidth + spacing) / (buttonWidth + spacing)))
        let candidates = canDelete ? priority : priority.filter { $0 != .delete }
        return Set(candidates.prefix(slots))
    }
}
