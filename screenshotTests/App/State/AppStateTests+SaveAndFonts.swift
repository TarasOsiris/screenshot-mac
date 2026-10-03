import AppKit
import CoreGraphics
@testable import Screenshot_Bro
import SwiftUI
import Testing

extension AppStateTests {
    @Test func saveImageDoesNotMutateStateWhenWriteFails() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        let shapeId = try #require(state.rows.first?.shapes.first?.id)
        let writeError = NSError(
            domain: "AppStateTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Disk full"]
        )
        ImageResourceIO.writeData = { _, _ in throw writeError }
        defer { ImageResourceIO.writeData = ImageResourceIO.defaultWriteData }

        state.saveImage(makeTestImage(width: 1200, height: 2600), for: shapeId, source: .picker)

        let shape = try #require(state.rows.first?.shapes.first(where: { $0.id == shapeId }))
        #expect(shape.displayImageFileName == nil)
        #expect(state.screenshotImages.isEmpty)
        #expect(state.saveError?.contains("Disk full") == true)
    }

    @Test func saveAllDoesNotDeleteUnreferencedFontsWhenIndexSaveFails() throws {
        // A font record without a parseable file on disk, so the library is constructed with it
        // rather than mutated after the fact.
        let (state, tempDir) = makeState(fonts: CustomFontLibrary(
            customFonts: ["Unused.ttf": [CustomFont(
                fileName: "Unused.ttf",
                familyName: "Unused Family",
                styleName: nil,
                postScriptName: nil,
                isBold: false,
                isItalic: false
            )]],
            everReferenced: ["Unused Family"]
        ))
        defer { cleanup(tempDir) }

        let projectId = try #require(state.activeProjectId)
        let resourcesDir = PersistenceService.resourcesDir(projectId)
        let projectDir = PersistenceService.projectDirectoryURL(projectId)
        let fontURL = resourcesDir.appendingPathComponent("Unused.ttf")
        try Data("font".utf8).write(to: fontURL)

        let fm = FileManager.default
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: tempDir.path)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: projectDir.path)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: resourcesDir.path)
        defer {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempDir.path)
        }

        state.saveAll()

        #expect(state.saveError?.contains("Failed to save project index") == true)
        #expect(fm.fileExists(atPath: fontURL.path))
    }

    @Test func importedUnusedFontSurvivesProjectReload() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        let sourceFontURL = try bundledFontURL("Raleway-VariableFont_wght.ttf")
        #expect(FileManager.default.fileExists(atPath: sourceFontURL.path))
        let importedSelection = state.importCustomFont(from: sourceFontURL)
        #expect(importedSelection != nil)

        let projectId = try #require(state.activeProjectId)
        let importedURL = PersistenceService.resourcesDir(projectId).appendingPathComponent(sourceFontURL.lastPathComponent)
        #expect(FileManager.default.fileExists(atPath: importedURL.path))

        state.saveAll()
        state.unregisterCustomFonts()
        #expect(state.customFonts.isEmpty)
        state.loadCustomFonts()

        #expect(FileManager.default.fileExists(atPath: importedURL.path))
        #expect(state.customFonts.keys.contains(sourceFontURL.lastPathComponent))
    }

    /// A variable font is one file holding every weight; importing it used to keep only the
    /// file's first named instance — Thin — as the sole selectable face.
    @Test func importingVariableFontOffersEveryWeightAndSelectsRegular() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        let selection = try #require(state.importCustomFont(from: try bundledFontURL("Raleway-VariableFont_wght.ttf")))

        #expect(selection.fontName == "Raleway Regular")
        #expect(selection.fontWeight == 400)
        #expect(state.customFaces.map(\.styleName) == [
            "Thin", "ExtraLight", "Light", "Regular", "Medium", "SemiBold", "Bold", "ExtraBold", "Black",
        ])
        #expect(state.availableFontFamilySet.contains("Raleway Bold"))
        #expect(CustomFontRegistry.resolve("Raleway Bold").family == "Raleway")
        #expect(CustomFontRegistry.controlState(name: "Raleway Regular", fontWeight: 400, italic: false)?.showsWeightPicker == true)
    }

    /// Sets a text shape to `firstName`, lets cleanup record it as used, moves the text to
    /// `secondName`, and expects cleanup to still keep the imported file.
    func expectCleanupKeepsFont(
        _ fileName: String,
        whileTextMovesFrom firstName: String,
        to secondName: String,
        in state: AppState
    ) throws {
        state.selectRow(try #require(state.rows.first).id)
        var shape = CanvasShapeModel(type: .text, text: "Hello", fontName: firstName)
        state.addShape(shape)
        state.cleanupUnreferencedFonts()
        shape.fontName = secondName
        state.updateShape(shape)
        state.cleanupUnreferencedFonts()

        let projectId = try #require(state.activeProjectId)
        #expect(state.customFonts.keys.contains(fileName))
        #expect(FileManager.default.fileExists(atPath: PersistenceService.resourcesDir(projectId).appendingPathComponent(fileName).path))
    }

    /// A shape set to any instance but the first must still count as using the file, or cleanup
    /// deletes the font out from under it.
    @Test func cleanupKeepsVariableFontReferencedByANonFirstInstance() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        let sourceFontURL = try bundledFontURL("Raleway-VariableFont_wght.ttf")
        _ = try #require(state.importCustomFont(from: sourceFontURL))
        try expectCleanupKeepsFont(sourceFontURL.lastPathComponent, whileTextMovesFrom: "Raleway Thin", to: "Raleway Bold", in: state)
    }

    /// A `.ttc` can hold several families, and the picker offers every one. Moving all text from the
    /// file's first family to another must not read as the file falling out of use.
    @Test func cleanupKeepsFontCollectionReferencedByANonFirstFamily() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        let systemCollection = URL(fileURLWithPath: "/System/Library/Fonts/Supplemental/PTSans.ttc")
        try #require(FileManager.default.fileExists(atPath: systemCollection.path))
        let sourceDir = tempDir.appendingPathComponent("font-source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let sourceFontURL = sourceDir.appendingPathComponent(systemCollection.lastPathComponent)
        try FileManager.default.copyItem(at: systemCollection, to: sourceFontURL)

        let selection = try #require(state.importCustomFont(from: sourceFontURL))
        #expect(selection.fontName == "PT Sans Regular")
        #expect(state.customFaces.contains { $0.displayName == "PT Sans Narrow Regular" })
        try expectCleanupKeepsFont(
            sourceFontURL.lastPathComponent,
            whileTextMovesFrom: selection.fontName,
            to: "PT Sans Narrow Regular",
            in: state
        )
    }

    /// The load paths that can face undownloaded iCloud font files use the off-main scan;
    /// it must register and resolve the same fonts the synchronous one does.
    @Test func offMainFontLoadRegistersTheSameFonts() async throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        let sourceFontURL = try bundledFontURL("Raleway-VariableFont_wght.ttf")
        let selection = try #require(state.importCustomFont(from: sourceFontURL))
        state.unregisterCustomFonts()
        #expect(state.customFonts.isEmpty)

        await state.loadCustomFontsAsync()

        #expect(state.customFonts.keys.contains(sourceFontURL.lastPathComponent))
        #expect(state.availableFontFamilySet.contains(selection.fontName))
        // Populated from the faces the scan registered rather than a second read on the main actor.
        #expect(CustomFontRegistry.postScriptName(forFamily: "Raleway", managerWeight: 9, italic: false) != nil)
    }
}
