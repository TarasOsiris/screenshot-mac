import SwiftUI

#if os(macOS)
private let zoomButtonSize: CGFloat = 20
private let zoomLabelMinWidth: CGFloat = 32
#else
private let zoomButtonSize: CGFloat = 32
private let zoomLabelMinWidth: CGFloat = 42
#endif

struct ZoomControls: View {
    @Environment(ZoomController.self) private var zoom
    @State private var isPopoverPresented = false
    var onFit: (() -> Void)?
    var fitHelpText: LocalizedStringKey = "Fit canvas to the window"

    var body: some View {
        HStack(spacing: 0) {
            zoomButton("minus.magnifyingglass", label: "Zoom out", disabled: zoom.level <= ZoomConstants.min) {
                zoom.zoomOut()
            }

            Button {
                isPopoverPresented.toggle()
            } label: {
                Text(verbatim: "\(Int(zoom.level * 100))%")
                    .scaledFont(UIMetrics.FontSize.numericBadge, weight: .medium)
                    .monospacedDigit()
                    .foregroundStyle(zoom.level == 1.0 ? .tertiary : .secondary)
                    .frame(minWidth: zoomLabelMinWidth)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .focusable(false)
            .help("Zoom options")
            .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Zoom")
                        .scaledFont(UIMetrics.FontSize.menuRow, weight: .semibold)

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
                            zoom.reset()
                            isPopoverPresented = false
                        }
                        .buttonStyle(.borderless)
                    }
                    .scaledFont(UIMetrics.FontSize.menuRow)
                }
                .padding(12)
                .presentationCompactAdaptation(.popover)
            }

            zoomButton("plus.magnifyingglass", label: "Zoom in", disabled: zoom.level >= ZoomConstants.max) {
                zoom.zoomIn()
            }
        }
        .compactControlSize()
    }

    @ViewBuilder
    private var presetButtons: some View {
        ForEach(ZoomConstants.presets, id: \.self) { preset in
            Button("\(Int(preset * 100))%") {
                zoom.set(preset)
                isPopoverPresented = false
            }
            .buttonStyle(.bordered)
            .compactControlSize()
            .tint(zoom.level == preset ? .accentColor : nil)
        }
    }

    private func zoomButton(_ icon: String, label: LocalizedStringKey, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .labelStyle(.iconOnly)
                .scaledFont(UIMetrics.FontSize.body, weight: .semibold)
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
