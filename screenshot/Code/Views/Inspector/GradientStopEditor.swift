import SwiftUI

struct GradientStopEditor: View {
    @Binding var config: GradientConfig
    var onChanged: () -> Void
    @State private var selectedStopId: UUID?
    @FocusState private var isEditorFocused: Bool

    private let barHeight: CGFloat = 24
    private let handleSize: CGFloat = 14

    var body: some View {
        VStack(spacing: 8) {
            // Gradient bar with draggable stops
            GeometryReader { geo in
                let barWidth = geo.size.width

                ZStack(alignment: .leading) {
                    // Always horizontal so stop positions match visually
                    RoundedRectangle(cornerRadius: 6)
                        .fill(horizontalGradient)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 6))
                        .onTapGesture { location in
                            focusEditor()
                            let loc = location.x / barWidth
                            let newColor = interpolatedColor(at: loc)
                            let newId = config.addStop(color: newColor, at: loc)
                            selectedStopId = newId
                            onChanged()
                        }

                    ForEach(config.stops) { stop in
                        let isSelected = selectedStopId == stop.id
                        stopHandle(stop: stop, isSelected: isSelected)
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

            // Selected stop controls
            HStack(spacing: 8) {
                if let selectedId = selectedStopId,
                   config.stops.contains(where: { $0.id == selectedId }) {
                    ColorPicker(
                        "",
                        selection: selectedColorBinding(for: selectedId),
                        supportsOpacity: false
                    )
                    .labelsHidden()
                    .simultaneousGesture(TapGesture().onEnded { focusEditor() })

                    Text("\(selectedLocationPercent(for: selectedId))%")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 30)

                    Spacer()

                    Button {
                        focusEditor()
                        config.removeStop(id: selectedId)
                        selectedStopId = config.stops.first?.id
                        onChanged()
                    } label: {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .disabled(config.stops.count <= 2)
                    .help("Remove stop (min 2)")
                } else {
                    Text("Click bar to add stops")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }

                Text("\(config.stops.count) stops")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                Button {
                    focusEditor()
                    config.reverseStops()
                    onChanged()
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Reverse gradient")
            }
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
        .onDeleteCommand {
            deleteSelectedStop()
        }
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
                .frame(width: handleSize - 4, height: handleSize - 4)

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
