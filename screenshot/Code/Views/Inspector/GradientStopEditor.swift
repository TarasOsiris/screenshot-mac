import SwiftUI

struct GradientStopEditor: View {
    @Binding var config: GradientConfig
    var onChanged: () -> Void
    @State private var selectedStopId: UUID?
    @FocusState private var isEditorFocused: Bool

    private let handleSize = UIMetrics.GradientEditor.stopHandleSize
    private let barHeight = UIMetrics.GradientEditor.stopBarHeight
    private let handleHitTarget = UIMetrics.GradientEditor.stopHandleHitTarget
    private let controlsRowHeight = UIMetrics.GradientEditor.controlsRowHeight

    private var barCornerRadius: CGFloat { barHeight / 2 }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let barWidth = geo.size.width

                ZStack(alignment: .leading) {
                    // Always horizontal so stop positions match visually
                    RoundedRectangle(cornerRadius: barCornerRadius)
                        .fill(horizontalGradient)
                        .overlay {
                            RoundedRectangle(cornerRadius: barCornerRadius)
                                .strokeBorder(UIMetrics.Stroke.subtle, lineWidth: UIMetrics.BorderWidth.standard)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: barCornerRadius))
                        .onTapGesture { location in
                            focusEditor()
                            let loc = location.x / barWidth
                            let newColor = interpolatedColor(at: loc)
                            let newId = config.addStop(color: newColor, at: loc)
                            selectedStopId = newId
                            onChanged()
                        }

                    ForEach(config.stops) { stop in
                        let isSelected = effectiveSelectedStopId == stop.id
                        stopHandle(stop: stop, isSelected: isSelected)
                            .frame(width: handleHitTarget, height: handleHitTarget)
                            .contentShape(Circle())
                            .position(
                                x: stop.location * barWidth,
                                y: barHeight / 2
                            )
                            .gesture(
                                DragGesture(minimumDistance: 1)
                                    .onChanged { value in
                                        selectStop(stop.id)
                                        guard let idx = config.stops.firstIndex(where: { $0.id == stop.id }) else { return }
                                        config.stops[idx].location = max(0, min(1, value.location.x / barWidth))
                                        onChanged()
                                    }
                                    .onEnded { _ in
                                        config.stops.sort { $0.location < $1.location }
                                        onChanged()
                                    }
                            )
                            .onTapGesture {
                                selectStop(stop.id)
                            }
                    }
                }
            }
            .frame(height: barHeight)

            HStack(spacing: 8) {
                if let selectedId = effectiveSelectedStopId {
                    ColorPicker(
                        "",
                        selection: selectedColorBinding(for: selectedId),
                        supportsOpacity: false
                    )
                    .labelsHidden()
                    .iPadColorSwatchFrame()
                    .simultaneousGesture(TapGesture().onEnded { focusEditor() })

                    Text("\(selectedLocationPercent(for: selectedId))%")
                        .font(.system(size: UIMetrics.FontSize.body).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(minWidth: 30, alignment: .leading)

                    Spacer()

                    GradientStopIconButton(
                        icon: gradientStopRemoveIcon,
                        accessibilityLabel: "Remove stop",
                        help: "Remove stop (min 2)",
                        disabled: config.stops.count <= 2
                    ) {
                        focusEditor()
                        config.removeStop(id: selectedId)
                        selectedStopId = config.stops.first?.id
                        onChanged()
                    }
                } else {
                    Text("Click bar to add stops")
                        .font(.system(size: UIMetrics.FontSize.inlineLabel))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }

                GradientStopIconButton(
                    icon: "arrow.left.arrow.right",
                    accessibilityLabel: "Reverse gradient",
                    help: "Reverse gradient"
                ) {
                    focusEditor()
                    config.reverseStops()
                    onChanged()
                }
            }
            .frame(minHeight: controlsRowHeight, alignment: .center)
        }
        .focusable(true)
        .focused($isEditorFocused)
        .focusEffectDisabled()
        .onAppear {
            ensureSelectedStopIsValid()
        }
        .onChange(of: config.stops) {
            ensureSelectedStopIsValid()
        }
        #if os(macOS)
        .onDeleteCommand {
            deleteSelectedStop()
        }
        #endif
        .onKeyPress(.delete) {
            deleteSelectedStop()
            return .handled
        }
        .onKeyPress(.deleteForward) {
            deleteSelectedStop()
            return .handled
        }
    }

    private func deleteSelectedStop() {
        guard let selectedId = selectedStopId, config.stops.count > 2 else { return }
        focusEditor()
        config.removeStop(id: selectedId)
        selectedStopId = config.stops.first?.id
        onChanged()
    }

    private func focusEditor() {
        isEditorFocused = true
    }

    private func selectStop(_ id: UUID) {
        focusEditor()
        selectedStopId = id
    }

    private var effectiveSelectedStopId: UUID? {
        if let selectedStopId,
           config.stops.contains(where: { $0.id == selectedStopId }) {
            return selectedStopId
        }
        return config.stops.first?.id
    }

    private func ensureSelectedStopIsValid() {
        if let selectedStopId,
           config.stops.contains(where: { $0.id == selectedStopId }) {
            return
        }
        selectedStopId = config.stops.first?.id
    }

    private func selectedColorBinding(for id: UUID) -> Binding<Color> {
        Binding(
            get: {
                config.stops.first(where: { $0.id == id })?.color ?? .white
            },
            set: { newColor in
                guard let idx = config.stops.firstIndex(where: { $0.id == id }) else { return }
                config.stops[idx].color = newColor
                onChanged()
            }
        )
    }

    private func selectedLocationPercent(for id: UUID) -> Int {
        guard let stop = config.stops.first(where: { $0.id == id }) else { return 0 }
        return Int(stop.location * 100)
    }

    private var horizontalGradient: LinearGradient {
        LinearGradient(
            stops: config.swiftUIStops,
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    @ViewBuilder
    private func stopHandle(stop: GradientColorStop, isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: handleSize, height: handleSize)
                .shadow(color: .black.opacity(0.3), radius: 1, y: 1)

            Circle()
                .fill(stop.color)
                .frame(width: max(handleSize - 4, 8), height: max(handleSize - 4, 8))

            if isSelected {
                Circle()
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .frame(width: handleSize + 2, height: handleSize + 2)
            }
        }
    }

    private func interpolatedColor(at location: Double) -> Color {
        let stops = config.stops
        guard let first = stops.first, let last = stops.last, stops.count >= 2 else {
            return stops.first?.color ?? .white
        }

        if location <= first.location { return first.color }
        if location >= last.location { return last.color }

        for i in 0..<stops.count - 1 {
            if location >= stops[i].location && location <= stops[i + 1].location {
                let range = stops[i + 1].location - stops[i].location
                guard range > 0 else { return stops[i].color }
                let t = (location - stops[i].location) / range
                return blendColors(stops[i].color, stops[i + 1].color, t: t)
            }
        }
        return last.color
    }

    private func blendColors(_ c1: Color, _ c2: Color, t: Double) -> Color {
        let a = c1.sRGBComponents, b = c2.sRGBComponents
        let cg = CGFloat(t)
        return Color(
            red: Double(a.r + (b.r - a.r) * cg),
            green: Double(a.g + (b.g - a.g) * cg),
            blue: Double(a.b + (b.b - a.b) * cg)
        )
    }
}

private var gradientStopRemoveIcon: String {
    #if os(macOS)
    "minus.circle"
    #else
    "minus"
    #endif
}

private struct GradientStopIconButton: View {
    let icon: String
    let accessibilityLabel: LocalizedStringKey
    let help: LocalizedStringKey
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .medium))
                .frame(width: UIMetrics.GradientEditor.iconTapTarget, height: UIMetrics.GradientEditor.iconTapTarget)
                .contentShape(buttonShape)
        }
        .gradientStopIconButtonStyle()
        .focusable(false)
        .foregroundStyle(disabled ? .tertiary : .secondary)
        .disabled(disabled)
        .accessibilityLabel(accessibilityLabel)
        .help(help)
    }

    private var iconSize: CGFloat {
        #if os(macOS)
        UIMetrics.FontSize.inlineLabel
        #else
        15
        #endif
    }

    private var buttonShape: some Shape {
        #if os(macOS)
        Rectangle()
        #else
        Circle()
        #endif
    }
}

private extension View {
    @ViewBuilder
    func gradientStopIconButtonStyle() -> some View {
        #if os(macOS)
        buttonStyle(.plain)
        #else
        buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .controlSize(.small)
        #endif
    }

    /// Enlarges the inline ColorPicker to the iPad touch target; macOS keeps the native well size.
    @ViewBuilder
    func iPadColorSwatchFrame() -> some View {
        #if os(macOS)
        self
        #else
        frame(width: UIMetrics.ColorSwatch.inline, height: UIMetrics.ColorSwatch.inline)
        #endif
    }
}
