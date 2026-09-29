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
            let key = Self.colorKey(color)
            counts[key, default: (color, 0)].count += 1
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
        let saved = Set(palette.map(Self.colorKey))
        return counts.values
            .filter { !saved.contains(Self.colorKey($0.color)) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : Self.colorKey($0.color) < Self.colorKey($1.color) }
            .prefix(limit)
            .map(\.color)
    }

    /// Equal at 8-bit precision — what the picker can actually distinguish and what the file stores.
    static func sameColor(_ lhs: CodableColor, _ rhs: CodableColor) -> Bool {
        colorKey(lhs) == colorKey(rhs)
    }

    private static func colorKey(_ color: CodableColor) -> String {
        [color.red, color.green, color.blue, color.opacity]
            .map { String(format: "%02x", Int(($0 * 255).rounded())) }
            .joined()
    }
}
