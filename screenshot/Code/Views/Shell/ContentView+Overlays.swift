import SwiftUI

extension ContentView {
    #if os(iOS)
    /// Scroll room reserved under the canvas for the floating bottom chrome
    /// (shape-properties bar and, while editing text, the format bar above it).
    var floatingBottomChromeMargin: CGFloat {
        var margin: CGFloat = 0
        if state.hasSelection { margin += 72 }
        if state.textEdit.isActive { margin += RichTextFormatBarMetrics.height + 16 }
        return margin
    }
    #endif

    /// Keeps the image-loading pill clear of the floating properties bar on iPad; on macOS that
    /// bar is a sibling below the canvas, so the corner is already free.
    var imageLoadingPillBottomPadding: CGFloat {
        #if os(iOS)
        return state.hasSelection ? floatingBottomChromeMargin + 12 : 12
        #else
        return 12
        #endif
    }

    #if os(iOS)
    /// The rich-text format bar (while editing text) stacked above the shape-properties bar, both
    /// hovering over the canvas with a transparent surround. `richTextSelectionState` is read so
    /// the format bar appears once the controller publishes.
    var floatingBottomChrome: some View {
        VStack(spacing: 8) {
            if state.textEdit.isActive, state.textEdit.richTextSelectionState != nil,
               let controller = state.textEdit.richTextFormatController {
                RichTextDockedBar(controller: controller)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if state.hasSelection {
                ShapePropertiesBar(state: state)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
            }
        }
        .padding(.bottom, 8)
    }

    var positionedEditorModeButton: some View {
        editorModeFloatingButton
            .padding(.trailing, 16)
            .padding(.bottom, state.hasSelection ? floatingBottomChromeMargin + 8 : 16)
    }
    #endif

    /// Overlays drawn over the whole editor column, in stacking order.
    func editorOverlays(_ content: some View) -> some View {
        content
        #if os(macOS)
        .overlay {
            richTextFormatBarOverlay
        }
        #endif
        .overlay {
            if !state.localeState.isBaseLocale {
                Rectangle()
                    .strokeBorder(Color.localeWarning.opacity(0.5), lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            if exportFlow.isExporting {
                ExportProgressOverlay(
                    progress: exportFlow.progress,
                    total: exportFlow.total,
                    onCancel: { exportFlow.cancel() }
                )
            }
        }
        .overlay {
            // macOS + in-editor re-opens/switches only: blocks during the brief structural-open
            // phase (hides the teardown→reload flash). On iPad the cold first open is owned by
            // `ProjectOpenGate`, which paints this same spinner before ContentView is built.
            // Image downsampling streams in behind the live UI so row controls stay visible.
            if !exportFlow.isExporting {
                ProjectOpenOverlay(progress: state.projectOpen)
            }
        }
    }

    #if os(macOS)
    @ViewBuilder
    private var richTextFormatBarOverlay: some View {
        if state.textEdit.isActive,
           let selectionState = state.textEdit.richTextSelectionState,
           let anchor = state.textEdit.richTextFormatBarAnchor,
           let controller = state.textEdit.richTextFormatController {
            GeometryReader { proxy in
                let center = RichTextFormatBarPlacement.clampedCenter(
                    anchor: anchor,
                    containerOrigin: proxy.frame(in: .global).origin,
                    containerSize: proxy.size,
                    barSize: CGSize(width: RichTextFormatBarMetrics.width, height: RichTextFormatBarMetrics.height),
                    inset: RichTextFormatBarMetrics.edgeInset
                )
                RichTextFormatBar(
                    selectionState: selectionState,
                    onApplyFormat: { action in
                        controller.applyAction(action)
                    }
                )
                .frame(width: RichTextFormatBarMetrics.width, height: RichTextFormatBarMetrics.height)
                .position(center)
            }
            .zIndex(999)
        }
    }
    #endif
}
