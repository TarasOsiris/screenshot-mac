#if os(macOS)
import AppKit
import Observation
@testable import Screenshot_Bro
import SwiftUI
import Testing

/// Hosts the real `EditorRowHeader` so its natural height can be measured against the constant the
/// layout contract states. Without this the constant is a guess, and a wrong one silently clips the
/// row's chrome.
private struct HeaderMeasurementHost: View {
    let row: ScreenshotRow
    @State private var isEditingLabel = false
    @State private var editingLabelText = ""
    @FocusState private var focused: Bool

    var body: some View {
        EditorRowHeader(
            row: row, isSelected: false, canMoveUp: true, canMoveDown: true, canDelete: true,
            isEditingLabel: $isEditingLabel, editingLabelText: $editingLabelText,
            isLabelFieldFocused: $focused,
            onToggleCollapsed: {}, onStartLabelEdit: {}, onCommitLabelEdit: {}, onCancelLabelEdit: {},
            onMoveUp: {}, onMoveDown: {}, onDuplicate: {}, onReset: {}, onDelete: {},
            isPreviewMode: false, onTogglePreview: {}
        ) { EmptyView() }
    }
}

@MainActor @Observable
private final class ScrollGeometrySelectionProbe {
    var isSelected = false
    var publishedCenterXs: [CGFloat] = []
}

private struct ScrollGeometrySelectionHost: View {
    let probe: ScrollGeometrySelectionProbe
    let displayScale: CGFloat = 0.5

    var body: some View {
        let isSelected = probe.isSelected
        ScrollView(.horizontal) {
            Color.clear
                .frame(width: 1_600, height: 120)
                .padding(EditorRowLayout.scrollContentInsets)
        }
        .onScrollGeometryChange(for: CGFloat?.self) { geometry in
            guard isSelected else { return nil }
            let canvasX = max(
                0,
                geometry.visibleRect.midX - EditorRowLayout.scrollContentInsets.leading
            )
            return canvasX / displayScale
        } action: { _, centerX in
            guard let centerX else { return }
            probe.publishedCenterXs.append(centerX)
        }
    }
}

/// Records the width each layout pass proposes to it.
nonisolated final class ProposalRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var widths: [CGFloat?] = []
    func record(_ width: CGFloat?) { lock.lock(); widths.append(width); lock.unlock() }
    var recorded: [CGFloat?] { lock.lock(); defer { lock.unlock() }; return widths }
}

nonisolated struct ProposalProbe: Layout {
    let recorder: ProposalRecorder
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        recorder.record(proposal.width)
        return CGSize(width: proposal.width ?? 4000, height: 120)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews { subview.place(at: bounds.origin, proposal: .init(bounds.size)) }
    }
}

@Suite(.serialized)
@MainActor
struct EditorRowLayoutTests {

    private func row(height: CGFloat = 2688, templates: Int = 3, collapsed: Bool = false) -> ScreenshotRow {
        var row = ScreenshotRow(
            templates: (0..<templates).map { _ in ScreenshotTemplate() },
            templateHeight: height
        )
        row.isCollapsed = collapsed
        return row
    }

    // MARK: - The stated height must match the real header

    @Test func headerHeightMatchesTheRenderedHeader() {
        for width in [500.0, 900.0, 1400.0] {
            let host = NSHostingView(rootView: HeaderMeasurementHost(row: row()))
            host.frame = NSRect(x: 0, y: 0, width: width, height: 400)
            let window = makeTestWindow(hosting: host)
            defer { window.close() }
            host.layoutSubtreeIfNeeded()
            #expect(host.fittingSize.height == EditorRowLayout.headerHeight,
                    "header measured \(host.fittingSize.height) at width \(width)")
        }
    }

    // MARK: - Row height per mode

    @Test func collapsedRowIsHeaderOnly() {
        let collapsed = row(collapsed: true)
        #expect(EditorRowLayout.rowHeight(row: collapsed, zoom: 1, isPreviewMode: false)
                == EditorRowLayout.headerHeight)
        // Collapsing hides the canvas in preview mode too.
        #expect(EditorRowLayout.rowHeight(row: collapsed, zoom: 1, isPreviewMode: true)
                == EditorRowLayout.headerHeight)
    }

    @Test func editRowIsHeaderPlusCanvasControlBarsAndInsets() {
        let r = row()
        let expected = EditorRowLayout.headerHeight
            + r.displayHeight(zoom: 1)
            + UIMetrics.TemplateBar.height
            + EditorRowLayout.controlBarsBottomInset
            + EditorRowLayout.scrollContentInsets.top
            + EditorRowLayout.scrollContentInsets.bottom
            + EditorRowLayout.horizontalScrollerHeight
        #expect(EditorRowLayout.rowHeight(row: r, zoom: 1, isPreviewMode: false) == expected)
    }

    /// Preview mode renders tiles with no per-template control bars, so the row is exactly the bar
    /// and its inset shorter.
    @Test func previewRowOmitsTheControlBars() {
        let r = row()
        let edit = EditorRowLayout.rowHeight(row: r, zoom: 1, isPreviewMode: false)
        let preview = EditorRowLayout.rowHeight(row: r, zoom: 1, isPreviewMode: true)
        #expect(edit - preview == UIMetrics.TemplateBar.height + EditorRowLayout.controlBarsBottomInset)
    }

    // MARK: - Zoom

    @Test func onlyTheCanvasScalesWithZoom() {
        let r = row()
        for zoom in [ZoomConstants.min, 0.5, 1.0, 2.0, ZoomConstants.max] {
            let height = EditorRowLayout.rowHeight(row: r, zoom: zoom, isPreviewMode: false)
            let chrome = EditorRowLayout.rowHeight(row: r, zoom: zoom, isPreviewMode: false)
                - r.displayHeight(zoom: zoom)
            // The chrome is zoom-invariant; only the canvas grows.
            #expect(height > 0)
            #expect(chrome == EditorRowLayout.rowHeight(row: r, zoom: 1, isPreviewMode: false)
                    - r.displayHeight(zoom: 1))
        }
        #expect(EditorRowLayout.rowHeight(row: r, zoom: 2, isPreviewMode: false)
                > EditorRowLayout.rowHeight(row: r, zoom: 1, isPreviewMode: false))
    }

    /// A short template is capped at display scale 1, so zoom is the only thing that grows it.
    @Test func shortTemplateHeightTracksDisplayScaleCap() {
        let short = row(height: 400)
        #expect(short.displayScale(zoom: 1) == 1)
        #expect(EditorRowLayout.rowHeight(row: short, zoom: 1, isPreviewMode: false)
                == EditorRowLayout.headerHeight + 400
                + UIMetrics.TemplateBar.height + EditorRowLayout.controlBarsBottomInset
                + EditorRowLayout.scrollContentInsets.top + EditorRowLayout.scrollContentInsets.bottom
                + EditorRowLayout.horizontalScrollerHeight)
    }

    // MARK: - Scrollers

    /// Overlay scrollers float above the content and cost nothing; legacy ones are laid out inside
    /// the scroll view and must be reserved, or they clip the bottom of the control bars.
    @Test func scrollerAllowanceFollowsTheScrollerStyle() {
        let allowance = EditorRowLayout.horizontalScrollerHeight
        switch NSScroller.preferredScrollerStyle {
        case .overlay:
            #expect(allowance == 0)
        case .legacy:
            #expect(allowance == NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy))
            #expect(allowance > 0)
        @unknown default:
            #expect(allowance >= 0)
        }
    }

    /// Template count changes the row's width, never its height.
    @Test func templateCountDoesNotAffectHeight() {
        let one = EditorRowLayout.rowHeight(row: row(templates: 1), zoom: 1, isPreviewMode: false)
        let many = EditorRowLayout.rowHeight(row: row(templates: 12), zoom: 1, isPreviewMode: false)
        #expect(one == many)
    }
    /// The row used to re-key its scroll area once on first appearance, rebuilding the whole canvas
    /// subtree, because a `LazyVStack`'s first lazy pass can propose an *unbounded* width — which
    /// left the inner horizontal `ScrollView` sized to its content and unscrollable. Removing that
    /// workaround is only safe while the `Color.clear` shell hands its overlay a finite width from
    /// the very first pass. This pins that.
    @Test func shellHandsItsContentAFiniteWidthOnTheFirstLayoutPass() {
        let recorder = ProposalRecorder()
        let host = NSHostingView(rootView:
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { _ in
                        Color.clear
                            .frame(height: 200)
                            .overlay(alignment: .topLeading) {
                                ProposalProbe(recorder: recorder) { Color.red }
                            }
                    }
                }
            }
        )
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 400)
        let window = makeTestWindow(hosting: host)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        let widths = recorder.recorded
        #expect(!widths.isEmpty)
        for width in widths {
            let value = try? #require(width)
            #expect(value != nil, "shell proposed an unbounded width")
            #expect((value ?? .infinity).isFinite)
            #expect((value ?? 0) > 0)
        }
    }

    /// Selection participates in the transformed Equatable value, so a row that was already laid
    /// out while unselected publishes its viewport center as soon as it becomes selected. No
    /// horizontal geometry change is needed to re-arm shape placement for that row.
    @Test func selectingLaidOutScrollViewPublishesCenterWithoutGeometryChange() async throws {
        let probe = ScrollGeometrySelectionProbe()
        let host = NSHostingView(rootView: ScrollGeometrySelectionHost(probe: probe))
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 160)
        let window = makeTestWindow(hosting: host)
        defer { window.close() }

        try await settle(host)
        #expect(probe.publishedCenterXs.isEmpty)

        probe.isSelected = true
        try await settle(host)

        let centerX = try? #require(probe.publishedCenterXs.last)
        #expect(centerX != nil)
        #expect((centerX ?? 0) > 0)
        #expect((centerX ?? .infinity).isFinite)
    }
}
#endif
