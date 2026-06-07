import SwiftUI

#if os(macOS)
private let zoomButtonSize: CGFloat = 20
private let zoomLabelMinWidth: CGFloat = 32
#else
private let zoomButtonSize: CGFloat = 32
private let zoomLabelMinWidth: CGFloat = 42
#endif

enum ZoomConstants {
    static let min: CGFloat = 0.25
    static let max: CGFloat = 3.0
    static let step: CGFloat = 0.25
    static let presets: [CGFloat] = Array(stride(from: min, through: max, by: step))
}

struct ZoomControls: View {
    @Environment(AppState.self) private var state
    @State private var isPopoverPresented = false
    var onFit: (() -> Void)? = nil
    var fitHelpText: LocalizedStringKey = "Fit canvas to the window"

    var body: some View {
        @Bindable var state = state
        HStack(spacing: 0) {
            zoomButton("minus.magnifyingglass", label: "Zoom out", disabled: state.zoomLevel <= ZoomConstants.min) {
                state.zoomOut()
            }

            Button {
                isPopoverPresented.toggle()
            } label: {
                Text(verbatim: "\(Int(state.zoomLevel * 100))%")
                    .font(.system(size: UIMetrics.FontSize.numericBadge, weight: .medium).monospacedDigit())
                    .foregroundStyle(state.zoomLevel == 1.0 ? .tertiary : .secondary)
                    .frame(minWidth: zoomLabelMinWidth)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .focusable(false)
            .help("Zoom options")
            .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Zoom")
                        .font(.system(size: UIMetrics.FontSize.menuRow, weight: .semibold))

                    #if os(macOS)
                    HStack(spacing: 6) { presetButtons }
                    #else
                    // A single row of 11 presets would make a ~500pt-wide popover on iPad;
                    // wrap them into a compact grid instead.
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 60), spacing: 6)],
                        spacing: 6
                    ) {
                        presetButtons
                    }
                    .frame(width: 280)
                    #endif

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
                    .font(.system(size: UIMetrics.FontSize.menuRow))
                }
                .padding(12)
            }

            zoomButton("plus.magnifyingglass", label: "Zoom in", disabled: state.zoomLevel >= ZoomConstants.max) {
                state.zoomIn()
            }
        }
        .compactControlSize()
    }

    @ViewBuilder
    private var presetButtons: some View {
        ForEach(ZoomConstants.presets, id: \.self) { preset in
            Button("\(Int(preset * 100))%") {
                state.setZoomLevel(preset)
                isPopoverPresented = false
            }
            .buttonStyle(.bordered)
            .compactControlSize()
            .tint(state.zoomLevel == preset ? .accentColor : nil)
        }
    }

    private func zoomButton(_ icon: String, label: LocalizedStringKey, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .labelStyle(.iconOnly)
                .font(.system(size: UIMetrics.FontSize.body, weight: .semibold))
                .frame(width: zoomButtonSize, height: zoomButtonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .focusable(false)
        .foregroundStyle(.secondary)
        .disabled(disabled)
        .help(label)
    }
}
