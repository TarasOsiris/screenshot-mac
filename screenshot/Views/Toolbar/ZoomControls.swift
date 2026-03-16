import SwiftUI

enum ZoomConstants {
    static let min: CGFloat = 0.75
    static let max: CGFloat = 2.0
    static let step: CGFloat = 0.25
}

struct ZoomControls: View {
    @Environment(AppState.self) private var state
    @State private var isPopoverPresented = false
    var onFit: (() -> Void)? = nil
    var fitHelpText = "Fit canvas to the window"

    private let presets: [CGFloat] = [0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        @Bindable var state = state
        HStack(spacing: 0) {
            zoomButton("minus.magnifyingglass", disabled: state.zoomLevel <= ZoomConstants.min) {
                state.zoomOut()
            }

            Button {
                isPopoverPresented.toggle()
            } label: {
                Text(verbatim: "\(Int(state.zoomLevel * 100))%")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(state.zoomLevel == 1.0 ? .tertiary : .secondary)
                    .frame(minWidth: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .focusable(false)
            .help("Zoom options")
            .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Zoom")
                        .font(.system(size: 12, weight: .semibold))

                    HStack(spacing: 6) {
                        ForEach(presets, id: \.self) { preset in
                            Button("\(Int(preset * 100))%") {
                                state.setZoomLevel(preset)
                                isPopoverPresented = false
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(state.zoomLevel == preset ? .accentColor : nil)
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        if let onFit {
                            Button("Fit") {
                                onFit()
                                isPopoverPresented = false
                            }
                            .buttonStyle(.borderless)
                            .help(fitHelpText)
                        }

                        Button("Actual Size") {
                            state.resetZoom()
                            isPopoverPresented = false
                        }
                        .buttonStyle(.borderless)
                    }
                    .font(.system(size: 12))
                }
                .padding(12)
            }

            zoomButton("plus.magnifyingglass", disabled: state.zoomLevel >= ZoomConstants.max) {
                state.zoomIn()
            }
        }
        .controlSize(.small)
    }

    private func zoomButton(_ icon: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .focusable(false)
        .foregroundStyle(.secondary)
        .disabled(disabled)
    }
}
