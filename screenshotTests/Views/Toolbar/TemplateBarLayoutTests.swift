import CoreGraphics
@testable import Screenshot_Bro
import Testing

/// The bar sheds buttons one at a time as its column narrows. The widths below are usable widths
/// (`row.displayWidth(zoom:)` minus the bar's horizontal padding on each side) for a default
/// 1242×2688 row, whose column measures ≈231pt at 100% zoom.
struct TemplateBarLayoutTests {
    private let macButton: CGFloat = 22
    private let padButton: CGFloat = 44

    private func visible(
        _ availableWidth: CGFloat,
        buttonWidth: CGFloat,
        canDelete: Bool = true
    ) -> Set<TemplateBarLayout.Button> {
        TemplateBarLayout.visibleButtons(
            availableWidth: availableWidth,
            buttonWidth: buttonWidth,
            spacing: UIMetrics.TemplateBar.buttonSpacing,
            canDelete: canDelete
        )
    }

    /// The suite only runs on macOS, so the iPad width below can't be read from `UIMetrics`.
    /// Pin the macOS one so both stay honest if `ActionButton` is ever resized.
    @Test func widthsMatchTheShippingButton() {
        #expect(UIMetrics.ActionButton.frameSize == macButton)
    }

    @Test func fullBarAtHundredPercent() {
        #expect(visible(223, buttonWidth: macButton) == Set(TemplateBarLayout.Button.allCases))
    }

    @Test func seventyFivePercentDropsOnlyTheDownloadButton() {
        #expect(visible(165, buttonWidth: macButton) == [.more, .delete, .background, .preview, .moveLeft, .moveRight])
    }

    @Test func fiftyPercentKeepsPreviewBackgroundAndDelete() {
        #expect(visible(107, buttonWidth: macButton) == [.more, .delete, .background, .preview])
    }

    /// The ellipsis menu is the escape hatch for everything the bar drops, so it always survives.
    @Test func theNarrowestBarStillKeepsTheEllipsisMenu() {
        #expect(visible(49, buttonWidth: macButton) == [.more])
        #expect(visible(0, buttonWidth: macButton) == [.more])
    }

    @Test func downloadSitsExactlyOnTheSevenButtonBoundary() {
        #expect(!visible(189, buttonWidth: macButton).contains(.download))
        #expect(visible(190, buttonWidth: macButton).contains(.download))
    }

    /// The one property point samples can't express: narrowing only ever removes buttons.
    @Test func collapseIsMonotonic() {
        var previous = Set(TemplateBarLayout.Button.allCases)
        for width in stride(from: CGFloat(223), through: 22, by: -1) {
            let current = visible(width, buttonWidth: macButton)
            #expect(current.isSubset(of: previous), "buttons must never reappear as the bar narrows")
            previous = current
        }
    }

    @Test func aSingleTemplateFreesTheDeleteSlot() {
        #expect(visible(107, buttonWidth: macButton) == [.more, .delete, .background, .preview])
        #expect(visible(107, buttonWidth: macButton, canDelete: false) == [.more, .background, .preview, .moveLeft])
    }

    /// Background is the only bar control absent from the ellipsis menu, so it outlives the rest.
    @Test func backgroundIsTheLastOptionalButtonToGo() {
        #expect(visible(50, buttonWidth: macButton, canDelete: false) == [.more, .background])
    }

    /// iPad's 44pt touch targets fit far fewer buttons in the same column.
    @Test func iPadTouchTargetsCollapseSooner() {
        #expect(visible(223, buttonWidth: padButton) == [.more, .delete, .background, .preview])
        #expect(visible(94, buttonWidth: padButton) == [.more, .delete])
    }
}
