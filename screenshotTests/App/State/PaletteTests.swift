import Foundation
@testable import Screenshot_Bro
import SwiftUI
import Testing

@MainActor
struct PaletteTests {
    @Test func addingAndRemovingColorsAreUndoableSteps() throws {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let um = try #require(state.undoManager)
        um.removeAllActions()

        state.addPaletteColor(Color(red: 1, green: 0, blue: 0))
        state.addPaletteColor(Color(red: 1, green: 0, blue: 0))
        #expect(state.palette.count == 1, "The same color is saved once")
        #expect(um.canUndo)

        state.removePaletteColor(state.palette[0])
        #expect(state.palette.isEmpty)
        um.undo()
        #expect(state.palette.count == 1)
        um.undo()
        #expect(state.palette.isEmpty)
        #expect(!um.canUndo)
    }

    @Test func documentColorsRankByUseAndSkipSavedOnes() throws {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let red = Color(red: 1, green: 0, blue: 0)
        let blue = Color(red: 0, green: 0, blue: 1)
        state.rows[0].shapes = [
            CanvasShapeModel(type: .rectangle, color: red),
            CanvasShapeModel(type: .circle, color: red),
            CanvasShapeModel(type: .star, color: blue),
        ]
        let before = state.documentColors().map(\.color.hexString)
        #expect(before.firstIndex(of: red.hexString)! < before.firstIndex(of: blue.hexString)!)

        state.addPaletteColor(red)
        #expect(!state.documentColors().map(\.color.hexString).contains(red.hexString))
    }

    @Test func paletteRoundTripsAndOldProjectsDecodeEmpty() throws {
        let data = ProjectData(rows: [], palette: [CodableColor(Color(red: 0, green: 0.5, blue: 1))])
        let encoded = try JSONEncoder().encode(data)
        #expect(try JSONDecoder().decode(ProjectData.self, from: encoded).palette.count == 1)

        let legacy = try JSONEncoder().encode(ProjectData(rows: []))
        #expect(String(data: legacy, encoding: .utf8)?.contains("pal") == false)
        #expect(try JSONDecoder().decode(ProjectData.self, from: legacy).palette.isEmpty)
    }

    @Test func documentCarriesThePaletteThroughProjectData() {
        let data = ProjectData(rows: [], palette: [CodableColor(Color(red: 1, green: 1, blue: 0))])
        let document = ProjectDocument(data)
        #expect(document.palette.count == 1)
        #expect(document.projectData(name: nil).palette == data.palette)
    }
}
