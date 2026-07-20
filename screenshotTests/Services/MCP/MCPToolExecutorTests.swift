import AppKit
import Foundation
import MCP
import Testing
@testable import Screenshot_Bro

@Suite(.serialized)
@MainActor
struct MCPToolExecutorTests {

    private func makeExecutor() -> (MCPToolExecutor, AppState, URL) {
        let (state, tempDir) = makeTestState()
        return (MCPToolExecutor(state: state), state, tempDir)
    }

    private func expectSuccess(_ result: CallTool.Result) {
        #expect(result.isError != true, "unexpected tool error: \(result.content)")
    }

    // MARK: - Discovery

    @Test func listToolsCoversAllCatalogEntries() {
        let tools = MCPToolCatalog.tools
        #expect(tools.count == MCPToolName.allCases.count)
        #expect(Set(tools.map(\.name)) == Set(MCPToolName.allCases.map(\.rawValue)))
    }

    @Test func getProjectReturnsRowsAndShapes() async {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }
        let result = await executor.call(name: "get_project", arguments: nil)
        expectSuccess(result)
        guard case .text(let json, _, _) = result.content.first else {
            Issue.record("expected text content")
            return
        }
        #expect(json.contains(state.rows[0].id.uuidString))
        #expect(json.contains("\"width\" : 1242"))
    }

    @Test func unknownToolAndUnknownIdsReturnErrors() async {
        let (executor, _, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }

        let unknownTool = await executor.call(name: "does_not_exist", arguments: nil)
        #expect(unknownTool.isError == true)

        let unknownRow = await executor.call(name: "delete_row", arguments: ["row_id": .string(UUID().uuidString)])
        #expect(unknownRow.isError == true)

        let malformedId = await executor.call(name: "delete_row", arguments: ["row_id": "not-a-uuid"])
        #expect(malformedId.isError == true)
    }

    // MARK: - Projects

    @Test func createBlankProjectWithRowConfigurations() async {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }

        let result = await executor.call(name: "create_project", arguments: [
            "name": "MCP Made Me",
            "rows": .array([
                .object([
                    "label": "Hero",
                    "size": "1290x2796",
                    "template_count": 2,
                    "device_category": "iphone",
                ]),
            ]),
        ])
        expectSuccess(result)
        #expect(state.activeProject?.name == "MCP Made Me")
        #expect(state.rows.count == 1)
        #expect(state.rows[0].label == "Hero")
        #expect(state.rows[0].templateWidth == 1290)
        #expect(state.rows[0].templates.count == 2)
    }

    // MARK: - Rows

    @Test func addUpdateMoveDeleteRow() async {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }
        let firstRowId = state.rows[0].id

        let added = await executor.call(name: "add_row", arguments: [
            "label": "Second",
            "size": "1242x2688",
        ])
        expectSuccess(added)
        #expect(state.rows.count == 2)
        #expect(state.rows[1].label == "Second")

        let updated = await executor.call(name: "update_row", arguments: [
            "row_id": .string(state.rows[1].id.uuidString),
            "background_color": "#336699",
            "span_background": true,
        ])
        expectSuccess(updated)
        #expect(state.rows[1].backgroundStyle == .color)
        #expect(state.rows[1].backgroundColorData.color.hexString == "#336699")
        #expect(state.rows[1].spanBackgroundAcrossRow)

        let gradient = await executor.call(name: "update_row", arguments: [
            "row_id": .string(state.rows[1].id.uuidString),
            "background_gradient": .object([
                "type": "radial",
                "stops": .array([
                    .object(["color": "#ff0000", "location": 0]),
                    .object(["color": "#0000ff", "location": 1]),
                ]),
            ]),
        ])
        expectSuccess(gradient)
        #expect(state.rows[1].backgroundStyle == .gradient)
        #expect(state.rows[1].gradientConfig.gradientType == .radial)
        #expect(state.rows[1].gradientConfig.stops.count == 2)

        let moved = await executor.call(name: "move_row", arguments: [
            "row_id": .string(state.rows[1].id.uuidString),
            "direction": "up",
        ])
        expectSuccess(moved)
        #expect(state.rows[1].id == firstRowId)

        let deleted = await executor.call(name: "delete_row", arguments: [
            "row_id": .string(state.rows[0].id.uuidString),
        ])
        expectSuccess(deleted)
        #expect(state.rows.count == 1)
        #expect(state.rows[0].id == firstRowId)
    }

    @Test func addAndRemoveTemplateColumns() async {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }
        let rowId = state.rows[0].id.uuidString

        let added = await executor.call(name: "add_template", arguments: ["row_id": .string(rowId)])
        expectSuccess(added)
        #expect(state.rows[0].templates.count == 4)

        let removed = await executor.call(name: "remove_template", arguments: [
            "row_id": .string(rowId),
            "template_id": .string(state.rows[0].templates[3].id.uuidString),
        ])
        expectSuccess(removed)
        #expect(state.rows[0].templates.count == 3)
    }

    // MARK: - Shapes

    @Test func addShapeCreatesTextWithOverrides() async {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }
        let shapeCount = state.rows[0].shapes.count

        let result = await executor.call(name: "add_shape", arguments: [
            "row_id": .string(state.rows[0].id.uuidString),
            "type": "text",
            "template_index": 1,
            "text": "Hello from MCP",
            "font_size": 90,
            "color": "#112233",
        ])
        expectSuccess(result)
        #expect(state.rows[0].shapes.count == shapeCount + 1)

        let shape = state.rows[0].shapes.last!
        #expect(shape.type == .text)
        #expect(shape.text == "Hello from MCP")
        #expect(shape.fontSize == 90)
        #expect(shape.colorData.color.hexString == "#112233")
        let centerX = shape.x + shape.width / 2
        #expect(centerX > state.rows[0].templateWidth && centerX < state.rows[0].templateWidth * 2)
    }

    @Test func rejectsUnavailableFontName() async {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }

        _ = await executor.call(name: "add_shape", arguments: [
            "row_id": .string(state.rows[0].id.uuidString),
            "type": "text",
            "text": "Hello",
        ])
        let shape = state.rows[0].shapes.last!

        let unavailable = await executor.call(name: "update_shape", arguments: [
            "shape_id": .string(shape.id.uuidString),
            "font_name": "No Such Font Family",
        ])
        #expect(unavailable.isError == true)
        #expect(state.rows[0].shapes.last!.fontName == nil)

        let system = await executor.call(name: "update_shape", arguments: [
            "shape_id": .string(shape.id.uuidString),
            "font_name": "Helvetica",
        ])
        expectSuccess(system)
        #expect(state.rows[0].shapes.last!.fontName == "Helvetica")
    }

    @Test func addShapeWithBadFontAddsNothing() async {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }
        let shapeCount = state.rows[0].shapes.count

        let result = await executor.call(name: "add_shape", arguments: [
            "row_id": .string(state.rows[0].id.uuidString),
            "type": "text",
            "text": "Hello",
            "font_name": "No Such Font Family",
        ])
        #expect(result.isError == true)
        #expect(state.rows[0].shapes.count == shapeCount)
    }

    @Test func updateShapeEditsBaseEvenWhenViewingAnotherLocale() async {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }

        _ = await executor.call(name: "add_shape", arguments: [
            "row_id": .string(state.rows[0].id.uuidString),
            "type": "text",
            "text": "Hello",
        ])
        let shapeId = state.rows[0].shapes.last!.id

        expectSuccess(await executor.call(name: "add_locale", arguments: ["code": "de-DE"]))
        state.localeState.activeLocaleCode = "de-DE"

        let result = await executor.call(name: "update_shape", arguments: [
            "shape_id": .string(shapeId.uuidString),
            "x": 42,
            "font_size": 99,
        ])
        expectSuccess(result)

        let shape = state.rows[0].shapes.last!
        #expect(shape.x == 42)
        #expect(shape.fontSize == 99)
        #expect(state.localeState.overrides["de-DE"]?[shapeId.uuidString] == nil)
    }

    @Test func updateRowRejectsInvalidSizeWithoutPartialApply() async {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }
        let originalLabel = state.rows[0].label

        let result = await executor.call(name: "update_row", arguments: [
            "row_id": .string(state.rows[0].id.uuidString),
            "label": "Hero",
            "width": 50,
        ])
        #expect(result.isError == true)
        #expect(state.rows[0].label == originalLabel)
    }

    @Test func deleteLastRowFailsInsteadOfFalseAck() async {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }
        #expect(state.rows.count == 1)

        let result = await executor.call(name: "delete_row", arguments: [
            "row_id": .string(state.rows[0].id.uuidString),
        ])
        #expect(result.isError == true)
        #expect(state.rows.count == 1)
    }

    @Test func switchProjectSavesOutgoingEditsAndSettlesBeforeSnapshot() async throws {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }
        let firstProjectId = try #require(state.activeProjectId)
        let firstRowId = state.rows[0].id

        // Leave only a debounced (unsaved) edit behind before switching away.
        expectSuccess(await executor.call(name: "update_row", arguments: [
            "row_id": .string(firstRowId.uuidString),
            "label": "Edited before switch",
        ]))
        let created = await executor.call(name: "create_project", arguments: [
            "name": "Second",
            "rows": .array([.object(["template_count": 1])]),
        ])
        expectSuccess(created)
        #expect(state.activeProjectId != firstProjectId)

        // The debounced edit must have been flushed by the save-before-switch. Read the
        // file directly — PersistenceService routes through the process-global data-dir
        // env var, which parallel tests mutate.
        let firstProjectJSON = tempDir
            .appendingPathComponent("projects/\(firstProjectId.uuidString)/project.json")
        let savedData = try Data(contentsOf: firstProjectJSON)
        #expect(String(decoding: savedData, as: UTF8.self).contains("Edited before switch"))

        let switched = await executor.call(name: "switch_project", arguments: [
            "project_id": .string(firstProjectId.uuidString),
        ])
        expectSuccess(switched)
        // The snapshot must be taken only after the async project open has settled;
        // an in-flight open task here means the tool answered with stale rows.
        #expect(state.projectOpenTask == nil)
        #expect(state.activeProjectId == firstProjectId)
        guard case .text(let json, _, _) = switched.content.first else {
            Issue.record("expected text content")
            return
        }
        #expect(json.contains(firstProjectId.uuidString))
    }

    @Test func updateShapePatchesOnlyProvidedFields() async {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }

        _ = await executor.call(name: "add_shape", arguments: [
            "row_id": .string(state.rows[0].id.uuidString),
            "type": "rectangle",
        ])
        let original = state.rows[0].shapes.last!

        let result = await executor.call(name: "update_shape", arguments: [
            "shape_id": .string(original.id.uuidString),
            "x": 10,
            "y": 20,
            "rotation": 45,
            "border_radius": 12,
        ])
        expectSuccess(result)

        let updated = state.rows[0].shapes.last!
        #expect(updated.x == 10)
        #expect(updated.y == 20)
        #expect(updated.rotation == 45)
        #expect(updated.borderRadius == 12)
        #expect(updated.width == original.width)
        #expect(updated.colorData == original.colorData)
        #expect(state.localeState.overrides.isEmpty)
    }

    @Test func updateShapeTextEditsBaseLocale() async {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }

        _ = await executor.call(name: "add_shape", arguments: [
            "row_id": .string(state.rows[0].id.uuidString),
            "type": "text",
            "text": "Original",
        ])
        let shapeId = state.rows[0].shapes.last!.id

        let result = await executor.call(name: "update_shape", arguments: [
            "shape_id": .string(shapeId.uuidString),
            "text": "Rewritten",
        ])
        expectSuccess(result)
        #expect(state.rows[0].shapes.last!.text == "Rewritten")
        #expect(state.localeState.overrides.isEmpty)
    }

    @Test func deleteShapeRemovesIt() async {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }

        _ = await executor.call(name: "add_shape", arguments: [
            "row_id": .string(state.rows[0].id.uuidString),
            "type": "circle",
        ])
        let shapeId = state.rows[0].shapes.last!.id
        let countBefore = state.rows[0].shapes.count

        let result = await executor.call(name: "delete_shape", arguments: [
            "shape_id": .string(shapeId.uuidString),
        ])
        expectSuccess(result)
        #expect(state.rows[0].shapes.count == countBefore - 1)
        #expect(!state.rows[0].shapes.contains { $0.id == shapeId })
    }

    // MARK: - Locales & translations

    @Test func localeAndTranslationFlow() async {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }

        _ = await executor.call(name: "add_shape", arguments: [
            "row_id": .string(state.rows[0].id.uuidString),
            "type": "text",
            "text": "Base text",
        ])
        let shapeId = state.rows[0].shapes.last!.id

        let addLocale = await executor.call(name: "add_locale", arguments: ["code": "de-DE"])
        expectSuccess(addLocale)
        #expect(state.localeState.locales.contains { $0.code == "de-DE" })

        let duplicate = await executor.call(name: "add_locale", arguments: ["code": "de-DE"])
        #expect(duplicate.isError == true)

        let translation = await executor.call(name: "set_translation", arguments: [
            "shape_id": .string(shapeId.uuidString),
            "locale_code": "de-DE",
            "text": "Deutscher Text",
        ])
        expectSuccess(translation)
        let shape = state.rows[0].shapes.last!
        #expect(state.localeState.overrides["de-DE"]?[shape.textTranslationKey]?.text == "Deutscher Text")
        #expect(shape.text == "Base text")

        let baseTranslation = await executor.call(name: "set_translation", arguments: [
            "shape_id": .string(shapeId.uuidString),
            "locale_code": .string(state.localeState.baseLocaleCode),
            "text": "nope",
        ])
        #expect(baseTranslation.isError == true)

        let removeBase = await executor.call(name: "remove_locale", arguments: [
            "code": .string(state.localeState.baseLocaleCode),
        ])
        #expect(removeBase.isError == true)

        let removed = await executor.call(name: "remove_locale", arguments: ["code": "de-DE"])
        expectSuccess(removed)
        #expect(!state.localeState.locales.contains { $0.code == "de-DE" })
    }

    // MARK: - Screenshots & rendering

    @Test func importScreenshotsFillsDeviceFrames() async throws {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }

        let imageDir = makeTemporaryDataDirectory(label: "mcp-import")
        defer { try? FileManager.default.removeItem(at: imageDir) }
        var paths: [String] = []
        for index in 0..<2 {
            let url = imageDir.appendingPathComponent("shot\(index).png")
            let png = try #require(ExportService.pngData(from: makeTestImage(width: 1242, height: 2688)))
            try png.write(to: url)
            paths.append(url.path)
        }

        let result = await executor.call(name: "import_screenshots", arguments: [
            "row_id": .string(state.rows[0].id.uuidString),
            "paths": .array(paths.map(Value.string)),
        ])
        expectSuccess(result)
        let filled = state.rows[0].shapes.filter { $0.screenshotFileName != nil }
        #expect(filled.count == 2)

        let missing = await executor.call(name: "import_screenshots", arguments: [
            "row_id": .string(state.rows[0].id.uuidString),
            "paths": .array([.string("/nonexistent/nope.png")]),
        ])
        #expect(missing.isError == true)
    }

    @Test func renderPreviewReturnsDownscaledPNG() async throws {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }

        let result = await executor.call(name: "render_preview", arguments: [
            "row_id": .string(state.rows[0].id.uuidString),
            "max_dimension": 400,
        ])
        expectSuccess(result)

        guard case .image(let base64, let mimeType, _, _) = result.content.first else {
            Issue.record("expected image content, got \(result.content)")
            return
        }
        #expect(mimeType == "image/png")
        let data = try #require(Data(base64Encoded: base64))
        let image = try #require(NSImage(data: data))
        #expect(max(image.size.width, image.size.height) <= 401)
        #expect(min(image.size.width, image.size.height) > 0)
    }

    @Test func exportProjectWritesFiles() async throws {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }

        let result = await executor.call(name: "export_project", arguments: [:])
        expectSuccess(result)

        guard case .text(let json, _, _) = result.content.first else {
            Issue.record("expected text content")
            return
        }
        struct Payload: Decodable {
            let folder: String
            let files: [String]
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload = try decoder.decode(Payload.self, from: Data(json.utf8))
        #expect(payload.files.count == state.rows[0].templates.count)
        for file in payload.files {
            #expect(FileManager.default.fileExists(atPath: file))
            #expect(file.hasSuffix(".png"))
        }
        try? FileManager.default.removeItem(atPath: payload.folder)
    }

    // MARK: - App Store Connect metadata

    @Test func appStoreDescriptionRoundTripInDemoMode() async throws {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }

        let credentials = AppStoreConnectCredentialsStore.shared
        let originalDemoMode = credentials.isDemoMode
        credentials.isDemoMode = true
        defer { credentials.isDemoMode = originalDemoMode }

        // One editable iOS version with en-US + fr-FR localizations.
        AppStoreConnectDemoData.shared.updateContext(localeCodes: ["fr-FR"], rowSizes: [])

        let projectId = try #require(state.activeProject?.id)
        state.setASCAppId("demo-app-1", forProject: projectId)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let metaResult = await executor.call(name: "get_app_store_metadata", arguments: [:])
        expectSuccess(metaResult)
        guard case .text(let metaJson, _, _) = metaResult.content.first else {
            Issue.record("expected text content")
            return
        }
        struct Meta: Decodable {
            struct Version: Decodable {
                let versionId: String
                let editable: Bool
                let locales: [Locale]
                struct Locale: Decodable { let locale: String }
            }
            let appId: String
            let versions: [Version]
        }
        let meta = try decoder.decode(Meta.self, from: Data(metaJson.utf8))
        #expect(meta.appId == "demo-app-1")
        let discovered = try #require(meta.versions.first)
        #expect(discovered.editable)
        #expect(Set(discovered.locales.map(\.locale)) == ["en-US", "fr-FR"])

        let descriptions: Value = .array([
            .object(["locale": "en-US", "description": "Fresh English description."]),
            .object(["locale": "fr-FR", "description": "Nouvelle description française."]),
            .object(["locale": "zz-ZZ", "description": "Unmatched locale."]),
        ])
        let updateResult = await executor.call(
            name: "update_app_store_description",
            arguments: ["descriptions": descriptions]
        )
        expectSuccess(updateResult)
        guard case .text(let updateJson, _, _) = updateResult.content.first else {
            Issue.record("expected text content")
            return
        }
        struct UpdateResult: Decodable {
            struct VersionResult: Decodable {
                let updated: [String]
                let skipped: [Skip]
                struct Skip: Decodable { let locale: String; let reason: String }
            }
            let results: [VersionResult]
        }
        let update = try decoder.decode(UpdateResult.self, from: Data(updateJson.utf8))
        let versionResult = try #require(update.results.first)
        #expect(Set(versionResult.updated) == ["en-US", "fr-FR"])
        #expect(versionResult.skipped.map(\.locale) == ["zz-ZZ"])
    }
}
