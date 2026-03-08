import SwiftUI

enum ZoomConstants {
    static let min: CGFloat = 0.75
    static let max: CGFloat = 2.0
    static let step: CGFloat = 0.25
}

struct ZoomControls: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        HStack(spacing: 4) {
            zoomButton("minus", disabled: state.zoomLevel <= ZoomConstants.min) {
                state.zoomOut()
            }

            Slider(value: $state.zoomLevel, in: ZoomConstants.min...ZoomConstants.max)
                .frame(width: 80)
                .controlSize(.small)

            zoomButton("plus", disabled: state.zoomLevel >= ZoomConstants.max) {
                state.zoomIn()
            }

            Button {
                state.resetZoom()
            } label: {
                Text(verbatim: "\(Int(state.zoomLevel * 100))%")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(state.zoomLevel == 1.0 ? .tertiary : .secondary)
                    .frame(width: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .focusable(false)
            .help("Reset to 100%")
        }
        .controlSize(.small)
    }

    private func zoomButton(_ icon: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .focusable(false)
        .foregroundStyle(.secondary)
        .disabled(disabled)
    }
}
