import SwiftUI

extension ContentView {
    #if os(macOS)
    /// The coach's inspector step points at the row form, so the tour keeps it on screen.
    var inspectorIncludesShapes: Bool {
        isSelectionInspectorEnabled && state.coach.step != .inspector
    }

    var showsPropertiesBar: Bool {
        let rowIsPreviewing = state.selectedRowId.map { state.viewMode.previewingRows.contains($0) } ?? false
        return InspectorContent.showsPropertiesBar(
            hasShapeSelection: state.hasSelection,
            inspectorShowsShapes: InspectorContent.showsShapeProperties(includesShapes: inspectorIncludesShapes, rowIsPreviewing: rowIsPreviewing),
            inspectorPresented: isInspectorPresented
        )
    }
    #else
    var isInspectorCompact: Bool { horizontalSizeClass == .compact }
    #endif

    func inspectorPresentation(_ content: some View) -> some View {
        content
        #if os(macOS)
        .inspector(isPresented: $isInspectorPresented) {
            // Shape sections need more room than the row's.
            InspectorPanel(state: state, includesShapes: inspectorIncludesShapes)
                .inspectorColumnWidth(
                    min: isSelectionInspectorEnabled ? 250 : 220,
                    ideal: isSelectionInspectorEnabled ? 280 : 260,
                    max: isSelectionInspectorEnabled ? 360 : 320
                )
                .frame(minHeight: 200)
        }
        // Below `.inspector` so Esc also steps back while focus is in the sidebar.
        .onExitCommand {
            state.stepBackSelection()
        }
        .onChange(of: isSelectionInspectorEnabled) { _, isEnabled in
            // Turning it on is asking to see it.
            if isEnabled { isInspectorPresented = true }
        }
        #else
        // Docked side panel only at regular width. Apple's `.inspector` ignores
        // presentation-detent resizing when it auto-adapts to a sheet (it snaps back to
        // full height), so present a real `.sheet` at compact width instead, where detents
        // resize and the grabber persist properly.
        .inspector(isPresented: Binding(
            get: { !isInspectorCompact && isInspectorPresented },
            set: { if !isInspectorCompact { isInspectorPresented = $0 } }
        )) {
            InspectorPanel(state: state)
                .inspectorColumnWidth(min: 340, ideal: 380, max: 480)
                .frame(minHeight: 200)
        }
        .sheet(isPresented: Binding(
            get: { isInspectorCompact && isInspectorPresented },
            set: { isInspectorPresented = $0 }
        )) {
            InspectorPanel(state: state)
                .presentationDetents(BarSheet.detents(compact: isInspectorCompact), selection: $inspectorSheetDetent)
                .presentationDragIndicator(.visible)
        }
        #endif
    }

    func openInspectorIfCoachNeedsIt(_ step: OnboardingCoachStep?) {
        if step == .inspector {
            isInspectorPresented = true
        }
    }
}
