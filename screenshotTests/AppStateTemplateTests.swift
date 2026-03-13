import Testing
import AppKit
@testable import Screenshot_Bro

@MainActor
struct AppStateTemplateTests {

    @Test func savingProjectAsTemplateCreatesReusableProjectSnapshot() throws {
        let tempDirectory = makeTemporaryDataDirectory()
        setenv("SCREENSHOT_DATA_DIR", tempDirectory.path, 1)
        defer {
            unsetenv("SCREENSHOT_DATA_DIR")
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let state = AppState()
        state.addRow()
        state.addLocale(.init(code: "fr", label: "French"))
        let firstRowId = try #require(state.rows.first?.id)
        state.saveBackgroundImage(makeTestImage(width: 24, height: 24), for: firstRowId)

        state.saveCurrentProjectAsTemplate(name: "Marketing Template")

        #expect(state.projectTemplates.count == 1)
        let templateId = try #require(state.projectTemplates.first?.id)
        #expect(state.projectTemplates.first?.name == "Marketing Template")

        let templateData = try #require(PersistenceService.loadTemplate(templateId))
        #expect(templateData.rows.count == 2)
        #expect(templateData.localeState?.locales.map(\.code) == ["en", "fr"])
        let savedBackground = try #require(templateData.rows.first?.backgroundImageConfig.fileName)

        state.createProject(fromTemplate: templateId)

        #expect(state.projects.count == 2)
        #expect(state.activeProject?.name == "Marketing Template")
        #expect(state.rows.count == 2)
        #expect(state.localeState.locales.map(\.code) == ["en", "fr"])
        #expect(state.rows.first?.backgroundImageConfig.fileName == savedBackground)
        #expect(state.screenshotImages[savedBackground] != nil)

        state.createProject(fromTemplate: templateId)
        #expect(state.activeProject?.name == "Marketing Template 2")
    }

    @Test func resetTranslationRemovesOverrideFromProgress() throws {
        let tempDirectory = makeTemporaryDataDirectory()
        setenv("SCREENSHOT_DATA_DIR", tempDirectory.path, 1)
        defer {
            unsetenv("SCREENSHOT_DATA_DIR")
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let state = AppState()
        let row = try #require(state.rows.first)
        state.addShape(
            CanvasShapeModel.defaultText(
                centerX: row.templateWidth / 2,
                centerY: row.templateHeight / 2
            )
        )
        let shapeId = try #require(state.rows.first?.shapes.first(where: { $0.type == .text })?.id)

        state.addLocale(.init(code: "fr", label: "French"))
        #expect(state.translationProgress() == (0, 1))

        state.updateTranslationText(shapeId: shapeId, text: "Bonjour")
        #expect(state.translationProgress() == (1, 1))

        state.resetTranslationText(shapeId: shapeId)
        #expect(state.translationProgress() == (0, 1))
    }

}
