import SwiftUI
import Translation
import UniformTypeIdentifiers

struct ShapePropertiesBar: View {
    @Bindable var state: AppState
    #if os(iOS)
    @State private var panelHost = BarPanelHost()
    #endif

    var body: some View {
        #if os(iOS)
        VStack(alignment: .leading, spacing: 8) {
            if let panel = panelHost.panel {
                BarDockedPanel(panel: panel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            bar
        }
        .environment(panelHost)
        .animation(.easeInOut(duration: 0.2), value: panelHost.panel?.id)
        // A panel edits one shape's properties, so it must not outlive that selection.
        .onChange(of: state.selectedShapeId) { _, _ in panelHost.dismissAll() }
        .onDisappear { panelHost.dismissAll() }
        #else
        bar
        #endif
    }

    @ViewBuilder
    private var bar: some View {
        if state.selectedShapeIds.count > 1 {
            ShapePropertiesMultiSelectionBar(state: state)
        } else {
            ShapePropertiesSingleSelectionBar(state: state)
        }
    }
}
