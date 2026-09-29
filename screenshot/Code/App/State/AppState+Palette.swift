import SwiftUI

extension AppState {
    func addPaletteColor(_ color: Color) {
        let entry = CodableColor(color)
        guard !palette.contains(where: { Self.sameColor($0, entry) }) else { return }
        withUndo("Add Color to Palette") {
            palette.append(entry)
        }
    }

    func removePaletteColor(_ color: CodableColor) {
        guard palette.contains(where: { Self.sameColor($0, color) }) else { return }
        withUndo("Remove Color from Palette") {
            palette.removeAll { Self.sameColor($0, color) }
        }
    }

    /// The colors the project already uses, most used first, minus the ones already saved —
    /// what Sketch calls Document Colors.
    func documentColors(limit: Int = 12) -> [CodableColor] {
        var counts: [String: (color: CodableColor, count: Int)] = [:]
        func add(_ color: CodableColor?) {
            guard let color, color.opacity > 0 else { return }
            counts[color.hexKey, default: (color, 0)].count += 1
        }
        for row in rows {
            add(row.backgroundColorData)
            row.gradientConfig.stops.forEach { add($0.colorData) }
            for template in row.templates where template.overrideBackground {
                add(template.backgroundColor)
            }
            for shape in row.shapes {
                if shape.type != .image && shape.type != .device { add(shape.colorData) }
                add(shape.outlineColorData)
                add(shape.textBackgroundColorData)
                shape.fillGradientConfig?.stops.forEach { add($0.colorData) }
            }
        }
        let saved = Set(palette.map(\.hexKey))
        return counts
            .filter { !saved.contains($0.key) }
            .sorted { $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.key < $1.key }
            .prefix(limit)
            .map(\.value.color)
    }

    /// Equal at the 8-bit precision the file stores.
    static func sameColor(_ lhs: CodableColor, _ rhs: CodableColor) -> Bool {
        lhs.hexKey == rhs.hexKey
    }
}
