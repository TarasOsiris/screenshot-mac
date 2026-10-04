import CoreGraphics
@testable import Screenshot_Bro
import Testing

struct ShadowModifierOffsetTests {
    private func offset(rotation: Double, export: Bool) -> (x: CGFloat, y: CGFloat) {
        ShadowModifier.compensatedOffset(ox: 3, oy: 4, rotationDegrees: rotation, isExportRendering: export)
    }

    private func expectClose(_ actual: (x: CGFloat, y: CGFloat), _ expected: (x: CGFloat, y: CGFloat)) {
        #expect(abs(actual.x - expected.x) < 1e-9, "x: \(actual.x) vs \(expected.x)")
        #expect(abs(actual.y - expected.y) < 1e-9, "y: \(actual.y) vs \(expected.y)")
    }

    @Test(arguments: [0.0, 45, 90, 180, 270])
    func editorKeepsTheAuthoredOffset(rotation: Double) {
        expectClose(offset(rotation: rotation, export: false), (3, 4))
    }

    #if os(macOS)
    @Test func unrotatedExportMirrorsY() {
        expectClose(offset(rotation: 0, export: true), (3, -4))
    }

    /// Local (3, 4) at 90° is global (-4, 3); the offscreen flip needs global (-4, -3), which is
    /// local (-3, 4).
    @Test func quarterTurnExportLandsWhereTheEditorDraws() {
        expectClose(offset(rotation: 90, export: true), (-3, 4))
    }

    @Test func eighthTurnExportSwapsAndNegatesTheAxes() {
        expectClose(offset(rotation: 45, export: true), (-4, -3))
    }

    @Test func halfTurnExportMatchesTheUnrotatedCase() {
        expectClose(offset(rotation: 180, export: true), (3, -4))
    }
    #endif
}
