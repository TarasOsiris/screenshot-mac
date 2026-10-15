import AppKit
import Foundation
import MCP
@testable import Screenshot_Bro
import Testing

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
        #expect(tools.count == MCPToolName.available.count)
        #expect(Set(tools.map(\.name)) == Set(MCPToolName.available.map(\.rawValue)))
    }

    /// Uses the injection seam rather than `.shared`, so the session model is exercised end to end
    /// without one test leaking a session into the next.
    @Test func toolCallsOpenAndShareOneSession() async {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let sessions = MCPSessionTracker()
        let executor = MCPToolExecutor(state: state, sessions: sessions)

        #expect(sessions.currentSessionId == nil)
        _ = await executor.call(name: "list_projects", arguments: nil)
        let opened = sessions.currentSessionId
        #expect(opened != nil)

        // Even a rejected call belongs to the session — it is still an agent talking to us.
        _ = await executor.call(name: "not_a_tool", arguments: nil)
        #expect(sessions.currentSessionId == opened)
    }

    @Test func getProjectReturnsRowsAndShapes() async throws {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }
        let projectId = try #require(state.activeProject?.id)
        let result = await executor.call(
            name: "get_project",
            arguments: ["project_id": .string(projectId.uuidString)]
        )
        expectSuccess(result)
        guard case .text(let json, _, _) = result.content.first else {
            Issue.record("expected text content")
            return
        }
        #expect(json.contains(state.rows[0].id.uuidString))
        #expect(json.contains("\"width\":1242"))
    }

    /// The default that used to exist here is the bug: a snapshot silently describing whichever
    /// project the window happened to show, whose ids every other tool then uses.
    @Test func getProjectWithoutAProjectIdIsRejected() async {
        let (executor, _, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }
        let result = await executor.call(name: "get_project", arguments: nil)
        #expect(result.isError == true)
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

    @Test func textRunsRestyleOneWordAndRoundTrip() async {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }

        _ = await executor.call(name: "add_shape", arguments: [
            "row_id": .string(state.rows[0].id.uuidString),
            "type": "text",
            "text": "Track your training",
            "color": "#FFFFFF",
        ])
        let shapeId = state.rows[0].shapes.last!.id
        #expect(MCPRichText.runs(of: state.rows[0].shapes.last!) == nil)

        let styled = await executor.call(name: "update_shape", arguments: [
            "shape_id": .string(shapeId.uuidString),
            "text_runs": .array([
                .object(["text": "Track your "]),
                .object(["text": "training", "color": "#8FD3FF", "underline": true]),
            ]),
        ])
        expectSuccess(styled)
        var shape = state.rows[0].shapes.last!
        #expect(shape.text == "Track your training")
        let runs = MCPRichText.runs(of: shape)
        #expect(runs?.map(\.text) == ["Track your ", "training"])
        #expect(runs?.map(\.color) == ["#FFFFFF", "#8FD3FF"])
        #expect(runs?.last?.underline == true)

        // A shape-level color flattens every run, as the properties bar does.
        let recolored = await executor.call(name: "update_shape", arguments: [
            "shape_id": .string(shapeId.uuidString),
            "color": "#F5333A",
        ])
        expectSuccess(recolored)
        shape = state.rows[0].shapes.last!
        #expect(Set(MCPRichText.runs(of: shape)?.map(\.color) ?? []) == ["#F5333A"])

        let cleared = await executor.call(name: "update_shape", arguments: [
            "shape_id": .string(shapeId.uuidString),
            "clear_text_formatting": true,
        ])
        expectSuccess(cleared)
        #expect(state.rows[0].shapes.last!.richText == nil)
        #expect(state.rows[0].shapes.last!.text == "Track your training")
    }

    @Test func textRunsRejectBadInputWithoutApplying() async {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }

        _ = await executor.call(name: "add_shape", arguments: [
            "row_id": .string(state.rows[0].id.uuidString),
            "type": "text",
            "text": "Original",
        ])
        let shapeId = state.rows[0].shapes.last!.id

        let badColor = await executor.call(name: "update_shape", arguments: [
            "shape_id": .string(shapeId.uuidString),
            "x": 10,
            "text_runs": .array([.object(["text": "New", "color": "blue"])]),
        ])
        #expect(badColor.isError == true)
        let both = await executor.call(name: "update_shape", arguments: [
            "shape_id": .string(shapeId.uuidString),
            "text": "New",
            "text_runs": .array([.object(["text": "New"])]),
        ])
        #expect(both.isError == true)
        #expect(state.rows[0].shapes.last!.text == "Original")
        #expect(state.rows[0].shapes.last!.x != 10)
    }

    @Test func textRunsRoundTripKeepsUprightAndSystemFontSpans() async {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }

        _ = await executor.call(name: "add_shape", arguments: [
            "row_id": .string(state.rows[0].id.uuidString),
            "type": "text",
            "text": "Go Pro",
            "font_name": "Helvetica",
        ])
        let shapeId = state.rows[0].shapes.last!.id
        state.rows[0].shapes[state.rows[0].shapes.count - 1].italic = true

        _ = await executor.call(name: "update_shape", arguments: [
            "shape_id": .string(shapeId.uuidString),
            "text_runs": .array([
                .object(["text": "Go "]),
                .object(["text": "Pro", "italic": false, "font_name": "system"]),
            ]),
        ])
        let first = MCPRichText.runs(of: state.rows[0].shapes.last!)!
        #expect(first.map(\.italic) == [true, false])
        // RTF persists the system font as Helvetica Neue; what matters is it isn't the shape's font.
        #expect(first.last?.fontName != "Helvetica")

        // Send the spans back exactly as read, with only one color changed.
        let echoed: [Value] = first.enumerated().map { index, run in
            .object([
                "text": .string(run.text),
                "color": .string(index == 0 ? "#FF0000" : run.color),
                "font_name": .string(run.fontName),
                "font_size": .double(run.fontSize),
                "font_weight": .int(run.fontWeight),
                "italic": .bool(run.italic),
            ])
        }
        let result = await executor.call(name: "update_shape", arguments: [
            "shape_id": .string(shapeId.uuidString),
            "text_runs": .array(echoed),
        ])
        expectSuccess(result)
        let second = MCPRichText.runs(of: state.rows[0].shapes.last!)!
        #expect(second.map(\.italic) == [true, false])
        #expect(second.map(\.fontName) == first.map(\.fontName))
        #expect(second.first?.color == "#FF0000")
    }

    @Test func malformedOrEmptyTextRunsAreRejected() async {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }

        _ = await executor.call(name: "add_shape", arguments: [
            "row_id": .string(state.rows[0].id.uuidString),
            "type": "text",
            "text": "Original",
        ])
        let shapeId = state.rows[0].shapes.last!.id
        _ = await executor.call(name: "add_locale", arguments: ["code": "de-DE"])

        let malformed: [Value] = [
            .array(["Track your ", .object(["text": "training"])]),
            .string("[{\"text\":\"training\"}]"),
            .array([.object(["text": ""])]),
        ]
        for runs in malformed {
            let update = await executor.call(name: "update_shape", arguments: [
                "shape_id": .string(shapeId.uuidString),
                "text_runs": runs,
            ])
            #expect(update.isError == true)
            let translation = await executor.call(name: "set_translation", arguments: [
                "shape_id": .string(shapeId.uuidString),
                "locale_code": "de-DE",
                "text_runs": runs,
            ])
            #expect(translation.isError == true)
        }
        #expect(state.rows[0].shapes.last!.text == "Original")
        #expect(state.localeState.overrides["de-DE"]?.isEmpty != false)
    }

    @Test func updateShapeWithStyleAndRunsIsOneUndoStep() async {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }

        _ = await executor.call(name: "add_shape", arguments: [
            "row_id": .string(state.rows[0].id.uuidString),
            "type": "text",
            "text": "Original",
        ])
        let before = state.rows[0].shapes.last!
        _ = await executor.call(name: "update_shape", arguments: [
            "shape_id": .string(before.id.uuidString),
            "x": 42,
            "color": "#123456",
            "text_runs": .array([.object(["text": "New "]), .object(["text": "text", "color": "#F5333A"])]),
        ])
        #expect(state.rows[0].shapes.last!.text == "New text")

        state.undoManager?.undo()
        #expect(state.rows[0].shapes.last! == before)
    }

    @Test func clearAndRestyleReachTranslations() async {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }

        _ = await executor.call(name: "add_shape", arguments: [
            "row_id": .string(state.rows[0].id.uuidString),
            "type": "text",
            "text": "Base",
            "color": "#FFFFFF",
        ])
        let shapeId = state.rows[0].shapes.last!.id
        _ = await executor.call(name: "add_locale", arguments: ["code": "de-DE"])
        _ = await executor.call(name: "set_translation", arguments: [
            "shape_id": .string(shapeId.uuidString),
            "locale_code": "de-DE",
            "text_runs": .array([.object(["text": "Dein "]), .object(["text": "Training", "color": "#8FD3FF"])]),
        ])
        func germanRuns() -> [MCPTextRun]? {
            MCPRichText.runs(of: LocaleService.resolveShape(state.rows[0].shapes.last!, localeCode: "de-DE", localeState: state.localeState))
        }
        #expect(germanRuns()?.count == 2)

        _ = await executor.call(name: "update_shape", arguments: [
            "shape_id": .string(shapeId.uuidString),
            "color": "#F5333A",
        ])
        #expect(germanRuns() == nil)

        _ = await executor.call(name: "set_translation", arguments: [
            "shape_id": .string(shapeId.uuidString),
            "locale_code": "de-DE",
            "text_runs": .array([.object(["text": "Dein "]), .object(["text": "Training", "underline": true])]),
        ])
        #expect(germanRuns()?.count == 2)
        _ = await executor.call(name: "update_shape", arguments: [
            "shape_id": .string(shapeId.uuidString),
            "clear_text_formatting": true,
        ])
        let resolved = LocaleService.resolveShape(state.rows[0].shapes.last!, localeCode: "de-DE", localeState: state.localeState)
        #expect(resolved.richText == nil)
        #expect(resolved.text == "Dein Training")
    }

    @Test func translationTextRuns() async {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }

        _ = await executor.call(name: "add_shape", arguments: [
            "row_id": .string(state.rows[0].id.uuidString),
            "type": "text",
            "text": "Base text",
        ])
        let shapeId = state.rows[0].shapes.last!.id
        _ = await executor.call(name: "add_locale", arguments: ["code": "de-DE"])

        let result = await executor.call(name: "set_translation", arguments: [
            "shape_id": .string(shapeId.uuidString),
            "locale_code": "de-DE",
            "text_runs": .array([
                .object(["text": "Dein "]),
                .object(["text": "Training", "color": "#F5333A"]),
            ]),
        ])
        expectSuccess(result)
        let shape = state.rows[0].shapes.last!
        #expect(shape.text == "Base text")
        #expect(shape.richText == nil)
        let resolved = LocaleService.resolveShape(shape, localeCode: "de-DE", localeState: state.localeState)
        #expect(resolved.text == "Dein Training")
        #expect(MCPRichText.runs(of: resolved)?.last?.color == "#F5333A")
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

    @Test func setTranslationFitsOverflowingText() async throws {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }
        let shape = CanvasShapeModel(type: .text, x: 100, y: 400, width: 600, height: 120, text: "Edit fast", fontSize: 80, fontWeight: 700)
        state.rows[0].shapes = [shape]
        _ = await executor.call(name: "add_locale", arguments: ["code": "de-DE"])
        let german = "Bearbeite deine Bildschirmfotos blitzschnell und mühelos"

        let untouched = await executor.call(name: "set_translation", arguments: [
            "shape_id": .string(shape.id.uuidString), "locale_code": "de-DE", "text": .string(german), "auto_fit": false,
        ])
        expectSuccess(untouched)
        guard case .text(let untouchedJSON, _, _) = untouched.content.first else { Issue.record("expected text"); return }
        #expect(untouchedJSON.contains("\"text_overflow_locales\""))
        #expect(!untouchedJSON.contains("\"auto_fit\""))

        let fitted = await executor.call(name: "set_translation", arguments: [
            "shape_id": .string(shape.id.uuidString), "locale_code": "de-DE", "text": .string(german),
        ])
        expectSuccess(fitted)
        guard case .text(let json, _, _) = fitted.content.first else { Issue.record("expected text"); return }
        #expect(json.contains("\"auto_fit\""))
        #expect(json.contains("\"still_overflows\":false"))
        #expect(!json.contains("\"text_overflow_locales\""))
        #expect(json.contains("\"id\":\"\(shape.id.uuidString)\""))
        let base = try #require(state.rows[0].shapes.first)
        #expect(base.y == shape.y && base.height == shape.height)
    }

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
        guard case .text(let message, _, _) = missing.content.first else {
            Issue.record("expected text content")
            return
        }
        // The agent gets the failing paths plus a staging dir that works under the sandbox.
        #expect(message.contains("/nonexistent/nope.png"))
        #expect(message.contains(FileManager.default.temporaryDirectory.path))
    }

    /// An MCP caller cannot see which locale the window is on, so an import must go where it says
    /// and report where it went. Without this, a sweep over 14 languages filed every one of them
    /// under whichever locale the editor happened to be showing and answered `imported: 8` each
    /// time — the wrong screenshots reached a live store listing with no error anywhere.
    @Test func importScreenshotsTargetsTheRequestedLocale() async throws {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }

        _ = await executor.call(name: "add_locale", arguments: ["code": .string("de-DE")])
        _ = await executor.call(name: "add_locale", arguments: ["code": .string("fr-FR")])
        // The window sits on German; the import asks for French.
        state.setActiveLocale("de-DE")

        let imageDir = makeTemporaryDataDirectory(label: "mcp-import-locale")
        defer { try? FileManager.default.removeItem(at: imageDir) }
        let url = imageDir.appendingPathComponent("shot.png")
        let png = try #require(ExportService.pngData(from: makeTestImage(width: 1242, height: 2688)))
        try png.write(to: url)

        let result = await executor.call(name: "import_screenshots", arguments: [
            "row_id": .string(state.rows[0].id.uuidString),
            "paths": .array([.string(url.path)]),
            "locale": .string("fr-FR"),
        ])
        expectSuccess(result)

        let shapeId = try #require(state.rows[0].shapes.first { $0.type == .device }?.id)
        let french = state.localeState.override(forCode: "fr-FR", shapeId: shapeId)?.overrideImageFileName
        let german = state.localeState.override(forCode: "de-DE", shapeId: shapeId)?.overrideImageFileName
        #expect(french != nil, "the requested locale should hold the image")
        #expect(german == nil, "the locale merely on screen must not be written")
        #expect(french?.contains("-fr-FR-") == true)
    }

    /// A locale-targeted import into a row whose frames are still empty writes an override, and
    /// an override alone would leave the base locale — and every other one — exporting blank
    /// frames while the call still answered `imported: 8`.
    @Test func importScreenshotsSeedsTheBaseImageWhenThereIsNone() async throws {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }

        _ = await executor.call(name: "add_locale", arguments: ["code": .string("de-DE")])

        let imageDir = makeTemporaryDataDirectory(label: "mcp-import-seed-base")
        defer { try? FileManager.default.removeItem(at: imageDir) }
        let url = imageDir.appendingPathComponent("shot.png")
        let png = try #require(ExportService.pngData(from: makeTestImage(width: 1242, height: 2688)))
        try png.write(to: url)

        let result = await executor.call(name: "import_screenshots", arguments: [
            "row_id": .string(state.rows[0].id.uuidString),
            "paths": .array([.string(url.path)]),
            "locale": .string("de-DE"),
        ])
        expectSuccess(result)

        let shape = try #require(state.rows[0].shapes.first { $0.type == .device })
        let german = state.localeState.override(forCode: "de-DE", shapeId: shape.id)?.overrideImageFileName
        #expect(german != nil)
        #expect(shape.displayImageFileName == german, "a frame with no image needs a base fallback")

        // And the row the call returns shows where the image landed.
        guard case .text(let json, _, _) = result.content.first else {
            Issue.record("expected text content")
            return
        }
        #expect(json.contains("\"image_overrides\""))
        #expect(json.contains("\"de-DE\""))
    }

    /// A `locale` that is present but not a usable string must fail, not quietly fall back to the
    /// active locale — that fallback is the whole bug.
    @Test func importScreenshotsRejectsAMalformedLocale() async throws {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }

        let imageDir = makeTemporaryDataDirectory(label: "mcp-import-malformed-locale")
        defer { try? FileManager.default.removeItem(at: imageDir) }
        let url = imageDir.appendingPathComponent("shot.png")
        let png = try #require(ExportService.pngData(from: makeTestImage(width: 1242, height: 2688)))
        try png.write(to: url)

        // `null` is not in this list on purpose: it reads as "unspecified", the same as omitting
        // the key, which is how `render_preview` treats it too.
        for bad: Value in [.int(5), .string(""), .bool(true)] {
            let result = await executor.call(name: "import_screenshots", arguments: [
                "row_id": .string(state.rows[0].id.uuidString),
                "paths": .array([.string(url.path)]),
                "locale": bad,
            ])
            #expect(result.isError == true, "expected \(bad) to be rejected")
        }
    }

    /// Unknown locales fail loudly rather than silently landing in the active one.
    @Test func importScreenshotsRejectsAnUnknownLocale() async throws {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }

        let imageDir = makeTemporaryDataDirectory(label: "mcp-import-bad-locale")
        defer { try? FileManager.default.removeItem(at: imageDir) }
        let url = imageDir.appendingPathComponent("shot.png")
        let png = try #require(ExportService.pngData(from: makeTestImage(width: 1242, height: 2688)))
        try png.write(to: url)

        let result = await executor.call(name: "import_screenshots", arguments: [
            "row_id": .string(state.rows[0].id.uuidString),
            "paths": .array([.string(url.path)]),
            "locale": .string("xx-XX"),
        ])
        #expect(result.isError == true)
    }

    /// Unreadable paths are the agent's environment (usually a Release sandbox denial), not our
    /// bug — and the message names the user's files, so it must never become a Sentry report.
    @Test func unreadableFilesIsAClientError() {
        #expect(MCPToolError.unreadableFiles("detail").isClientError)
        #expect(!MCPToolError.failed("detail").isClientError)
    }

    /// Setup/business-rule conditions stay off Sentry, like client errors (SCREENSHOT-BRO-G).
    @Test func expectedConditionIsAClientError() {
        #expect(MCPToolError.expected("detail").isClientError)
    }

    @Test func renderPreviewReturnsDownscaledPNG() async throws {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }

        let projectId = try #require(state.activeProject?.id)
        let result = await executor.call(name: "render_preview", arguments: [
            "project_id": .string(projectId.uuidString),
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

        let projectId = try #require(state.activeProject?.id)
        let result = await executor.call(
            name: "export_project",
            arguments: ["project_id": .string(projectId.uuidString)]
        )
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

    /// A sandbox-denied `folder_path` is the same class as an unreadable import path: the agent's
    /// environment, not our bug, and the message names the path — so it must throw
    /// `unreadableFiles`, not `failed`, or it leaks into a Sentry report.
    @Test func exportProjectUnwritableFolderIsAClientError() async throws {
        let (executor, _, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }

        let blockerFile = tempDir.appendingPathComponent("blocker-file")
        try Data().write(to: blockerFile)
        let projectId = try #require(executor.state.activeProject?.id)

        do {
            _ = try await executor.exportProject(MCPArguments([
                "project_id": .string(projectId.uuidString),
                "folder_path": .string(blockerFile.path),
            ]))
            Issue.record("expected export to a path occupied by a file to throw")
        } catch let error as MCPToolError {
            #expect(error.isClientError)
        }
    }

    /// A client cancelling a long-running export (e.g. closing the MCP connection mid-render) must
    /// reach `call()` as a bare `CancellationError`, not get wrapped into `MCPToolError.failed` —
    /// wrapping it lost the type and made every cancelled export open an `mcpToolFailed` Sentry
    /// report for expected, not-our-bug behavior (SCREENSHOT-BRO-G).
    @Test func exportProjectCancellationIsNotWrappedAsFailure() async throws {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }

        let projectId = try #require(state.activeProject?.id)
        let exportTask = Task { @MainActor in
            try await executor.exportProject(MCPArguments([
                "project_id": .string(projectId.uuidString),
            ]))
        }

        await Task.yield()
        exportTask.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await exportTask.value
        }
    }

    // MARK: - Argument validation

    @Test func rejectsUnknownArgumentWithoutApplying() async {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }
        let shapeCount = state.rows[0].shapes.count

        let result = await executor.call(name: "add_shape", arguments: [
            "row_id": .string(state.rows[0].id.uuidString),
            "type": "text",
            "colour": "#112233",
        ])
        #expect(result.isError == true)
        #expect("\(result.content)".contains("colour"))
        #expect(state.rows[0].shapes.count == shapeCount)
    }

    @Test func rejectsWrongTypesAndEnumValues() async {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }
        let rowId = Value.string(state.rows[0].id.uuidString)

        let stringForNumber = await executor.call(name: "update_row", arguments: ["row_id": rowId, "width": "1242"])
        #expect(stringForNumber.isError == true)
        let fractionalInteger = await executor.call(name: "add_shape", arguments: ["row_id": rowId, "type": "text", "font_weight": 450.5])
        #expect(fractionalInteger.isError == true)
        let badEnum = await executor.call(name: "move_row", arguments: ["row_id": rowId, "direction": "sideways"])
        #expect(badEnum.isError == true)
        let nestedUnknown = await executor.call(name: "update_row", arguments: [
            "row_id": rowId,
            "background_gradient": ["stops": [], "angel": 90],
        ])
        #expect(nestedUnknown.isError == true)
        #expect("\(nestedUnknown.content)".contains("background_gradient.angel"))

        let integralDouble = await executor.call(name: "add_shape", arguments: ["row_id": rowId, "type": "text", "font_weight": 700.0])
        expectSuccess(integralDouble)
        let explicitNull = await executor.call(name: "add_shape", arguments: ["row_id": rowId, "type": "text", "color": .null])
        expectSuccess(explicitNull)
    }

    @Test func lineHeightSetsTheMultipleTheRendererReads() async {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }
        _ = await executor.call(name: "add_shape", arguments: [
            "row_id": .string(state.rows[0].id.uuidString),
            "type": "text",
            "text": "Two\nlines",
        ])
        let shapeId = Value.string(state.rows[0].shapes.last!.id.uuidString)

        expectSuccess(await executor.call(name: "update_shape", arguments: ["shape_id": shapeId, "line_height": 1.4]))
        #expect(state.rows[0].shapes.last!.lineHeightMultiple == 1.4)
        #expect(state.rows[0].shapes.last!.lineSpacing == nil)

        expectSuccess(await executor.call(name: "update_shape", arguments: ["shape_id": shapeId, "line_height": 9]))
        #expect(state.rows[0].shapes.last!.lineHeightMultiple == TextLayoutStyle.lineHeightRange.upperBound)

        expectSuccess(await executor.call(name: "update_shape", arguments: ["shape_id": shapeId, "line_spacing": 20]))
        let converted = state.rows[0].shapes.last!
        #expect(converted.lineSpacing == nil)
        #expect((converted.lineHeightMultiple ?? 0) > 1)
    }

    @Test func deviceFrameIdIsValidatedAndSyncsCategoryAndAspect() async throws {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }
        _ = await executor.call(name: "add_shape", arguments: [
            "row_id": .string(state.rows[0].id.uuidString),
            "type": "device",
            "device_category": "iphone",
        ])
        let shapeId = Value.string(state.rows[0].shapes.last!.id.uuidString)

        let unknown = await executor.call(name: "update_shape", arguments: ["shape_id": shapeId, "device_frame_id": "no-such-frame"])
        #expect(unknown.isError == true)

        let ipad = try #require(DeviceFrameCatalog.allFrames.first { $0.fallbackCategory == .ipadPro13 })
        expectSuccess(await executor.call(name: "update_shape", arguments: ["shape_id": shapeId, "device_frame_id": .string(ipad.id)]))
        let shape = state.rows[0].shapes.last!
        #expect(shape.deviceFrameId == ipad.id)
        #expect(shape.deviceCategory == .ipadPro13)
        let expected = shape.resolvedBaseDimensions
        #expect(abs(shape.width / shape.height - expected.width / expected.height) < 0.01)
    }

    @Test func variantListIsAnObjectEnvelope() throws {
        let (_, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }
        let result = try MCPResultEncoding.result(MCPToolExecutor.variantList(state.document))
        guard case .object(let structured)? = result.structuredContent else {
            Issue.record("structuredContent must be an object, got \(String(describing: result.structuredContent))")
            return
        }
        #expect(structured["variants"]?.arrayValue?.first?.objectValue?["name"] == "Original")
    }

    // MARK: - Batch, catalog, undo

    @Test func batchAppliesInOrderWithReferencesAsOneUndoStep() async throws {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }
        let rowCount = state.rows.count

        let result = await executor.call(name: "batch", arguments: [
            "operations": [
                ["tool": "add_row", "arguments": ["label": "Batch row"]],
                ["tool": "add_shape", "arguments": ["row_id": "$0", "type": "text", "text": "$5 off"]],
                ["tool": "update_shape", "arguments": ["shape_id": "$1", "font_size": 120]],
            ],
        ])
        expectSuccess(result)
        #expect(state.rows.count == rowCount + 1)
        let row = try #require(state.rows.first { $0.label == "Batch row" })
        let text = try #require(row.shapes.first { $0.type == .text })
        #expect(text.text == "$5 off", "only id arguments are references")
        #expect(text.fontSize == 120)

        state.undoManager?.undo()
        #expect(state.rows.count == rowCount)
    }

    @Test func batchFailureAppliesNothing() async throws {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }
        let before = state.document

        let result = await executor.call(name: "batch", arguments: [
            "operations": [
                ["tool": "add_row", "arguments": [:]],
                ["tool": "update_shape", "arguments": ["shape_id": .string(UUID().uuidString), "x": 1]],
            ],
        ])
        #expect(result.isError == true)
        #expect("\(result.content)".contains("operations[1]"))
        #expect(state.document == before)

        let notEditing = await executor.call(name: "batch", arguments: ["operations": [["tool": "delete_project"]]])
        #expect(notEditing.isError == true)
    }

    @Test func setTranslationsAppliesEveryEntry() async throws {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }
        _ = await executor.call(name: "add_locale", arguments: ["code": "de-DE"])
        _ = await executor.call(name: "add_locale", arguments: ["code": "fr-FR"])
        _ = await executor.call(name: "add_shape", arguments: ["row_id": .string(state.rows[0].id.uuidString), "type": "text", "text": "Hello"])
        let shapeId = Value.string(state.rows[0].shapes.last!.id.uuidString)

        expectSuccess(await executor.call(name: "set_translations", arguments: [
            "entries": [
                ["shape_id": shapeId, "locale_code": "de-DE", "text": "Hallo"],
                ["shape_id": shapeId, "locale_code": "fr-FR", "text": "Bonjour"],
            ],
        ]))
        let key = state.rows[0].shapes.last!.textTranslationKey
        #expect(state.localeState.overrides["de-DE"]?[key]?.text == "Hallo")
        #expect(state.localeState.overrides["fr-FR"]?[key]?.text == "Bonjour")
    }

    @Test func listCatalogReportsAcceptedValues() async throws {
        let (executor, _, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }

        let frames = try decodeEnvelope(await executor.call(name: "list_catalog", arguments: ["kind": "device_frames", "category": "iphone"]))
        let frameIds = try #require((frames["device_frames"] as? [[String: Any]])?.compactMap { $0["id"] as? String })
        #expect(!frameIds.isEmpty)
        #expect(frameIds.allSatisfy { DeviceFrameCatalog.frame(for: $0)?.fallbackCategory == .iphone })

        let sizes = try decodeEnvelope(await executor.call(name: "list_catalog", arguments: ["kind": "screenshot_sizes"]))
        #expect((sizes["screenshot_sizes"] as? [[String: Any]])?.contains { $0["size"] as? String == "1242x2688" } == true)

        let fonts = try decodeEnvelope(await executor.call(name: "list_catalog", arguments: ["kind": "fonts"]))
        #expect((fonts["system"] as? [String])?.contains("Helvetica") == true)
    }

    @Test func undoAndRedoToolsDriveTheEditorStack() async throws {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }
        let shapeCount = state.rows[0].shapes.count
        _ = await executor.call(name: "add_shape", arguments: ["row_id": .string(state.rows[0].id.uuidString), "type": "star"])

        let undone = try decodeEnvelope(await executor.call(name: "undo", arguments: [:]))
        #expect(undone["undone"] as? String == "Add Shape")
        #expect(state.rows[0].shapes.count == shapeCount)
        expectSuccess(await executor.call(name: "redo", arguments: [:]))
        #expect(state.rows[0].shapes.count == shapeCount + 1)

        let wrongProject = await executor.call(name: "undo", arguments: ["project_id": .string(UUID().uuidString)])
        #expect(wrongProject.isError == true)
    }

    @Test func everyToolCarriesAnnotations() {
        for tool in MCPToolCatalog.tools {
            #expect(tool.annotations.readOnlyHint != nil, "\(tool.name) has no annotations")
        }
        let readOnly = Set(MCPToolCatalog.tools.filter { $0.annotations.readOnlyHint == true }.map(\.name))
        #expect(readOnly.contains("get_project"))
        #expect(!readOnly.contains("update_shape"))
    }

    @Test func getProjectFiltersRowsAndTranslations() async throws {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }
        let projectId = Value.string(try #require(state.activeProject?.id).uuidString)
        _ = await executor.call(name: "add_row", arguments: [:])
        _ = await executor.call(name: "add_locale", arguments: ["code": "de-DE"])
        _ = await executor.call(name: "add_shape", arguments: ["row_id": .string(state.rows[0].id.uuidString), "type": "text", "text": "Hi"])
        _ = await executor.call(name: "set_translation", arguments: [
            "shape_id": .string(state.rows[0].shapes.last!.id.uuidString), "locale_code": "de-DE", "text": "Hallo",
        ])

        let filtered = try decodeEnvelope(await executor.call(name: "get_project", arguments: [
            "project_id": projectId,
            "row_ids": [.string(state.rows[0].id.uuidString)],
            "include_translations": false,
        ]))
        let rows = try #require(filtered["rows"] as? [[String: Any]])
        #expect(rows.count == 1)
        let json = String(decoding: try JSONSerialization.data(withJSONObject: filtered), as: UTF8.self)
        #expect(!json.contains("Hallo"))
    }

    // MARK: - Design tools

    private func writeTestImage(_ tempDir: URL, name: String = "shot.png", width: CGFloat = 1290, height: CGFloat = 2796) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            NSColor.systemTeal.setFill()
            rect.fill()
            return true
        }
        try #require(ExportService.pngData(from: image)).write(to: url)
        return url
    }

    @Test func addShapeTakesEveryStyleFieldAndShadowNullRemoves() async throws {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }
        expectSuccess(await executor.call(name: "add_shape", arguments: [
            "row_id": .string(state.rows[0].id.uuidString),
            "type": "text",
            "text": "Styled",
            "rotation": 12,
            "italic": true,
            "uppercase": true,
            "vertical_align": "bottom",
            "shadow": ["color": "#112233", "radius": 20, "offset_y": 8],
            "text_background": ["color": "#FFFFFF", "padding": 24, "radius": 16],
        ]))
        let shape = state.rows[0].shapes.last!
        #expect(shape.rotation == 12)
        #expect(shape.italic == true)
        #expect(shape.uppercase == true)
        #expect(shape.textVerticalAlign == .bottom)
        #expect(shape.shadow?.isActive == true)
        #expect(shape.shadow?.radius == 20)
        #expect(shape.textBackgroundPadding == 24)

        let snapshot = try decodeEnvelope(await executor.call(name: "update_shape", arguments: [
            "shape_id": .string(shape.id.uuidString), "shadow": .null, "text_background": .null,
        ]))
        #expect(snapshot["shadow"] == nil)
        #expect(state.rows[0].shapes.last!.shadow == nil)
        #expect(state.rows[0].shapes.last!.textBackgroundColorData == nil)
    }

    @Test func backgroundImagesPerRowColumnAndLocale() async throws {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }
        let projectId = try #require(state.activeProject?.id)
        _ = await executor.call(name: "add_locale", arguments: ["code": "de-DE"])
        let base = try writeTestImage(tempDir, name: "bg.png", width: 400, height: 800)
        let german = try writeTestImage(tempDir, name: "bg-de.png", width: 400, height: 800)
        let rowId = Value.string(state.rows[0].id.uuidString)

        expectSuccess(await executor.call(name: "update_row", arguments: [
            "row_id": rowId, "background_image_path": .string(base.path), "background_fill_mode": "fit", "background_blur": 6,
        ]))
        expectSuccess(await executor.call(name: "update_row", arguments: [
            "row_id": rowId, "background_image_path": .string(german.path), "background_image_locale": "de-DE",
        ]))
        let config = state.rows[0].backgroundImageConfig
        #expect(state.rows[0].backgroundStyle == .image)
        #expect(state.rows[0].backgroundBlur == 6)
        #expect(config.fillMode == .fit)
        let baseFile = try #require(config.fileName)
        let germanFile = try #require(config.localeImages["de-DE"]?.fileName)
        #expect(baseFile != germanFile)
        for file in [baseFile, germanFile] {
            #expect(FileManager.default.fileExists(atPath: PersistenceService.resourcesDir(projectId).appendingPathComponent(file).path))
        }

        let templateId = Value.string(state.rows[0].templates[1].id.uuidString)
        expectSuccess(await executor.call(name: "update_template", arguments: ["row_id": rowId, "template_id": templateId, "background_color": "#FF0000"]))
        #expect(state.rows[0].templates[1].overrideBackground)
        #expect(state.rows[0].templates[1].backgroundStyle == .color)
    }

    @Test func duplicateAndReorderTools() async throws {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }
        let rowId = Value.string(state.rows[0].id.uuidString)
        let columns = state.rows[0].templates.count
        _ = await executor.call(name: "add_shape", arguments: ["row_id": rowId, "type": "text", "text": "Headline"])
        let headline = state.rows[0].shapes.last!
        let shapeCount = state.rows[0].shapes.count

        expectSuccess(await executor.call(name: "duplicate_shape", arguments: ["shape_id": .string(headline.id.uuidString), "to_columns": "all"]))
        #expect(state.rows[0].shapes.count == shapeCount + columns - 1)
        expectSuccess(await executor.call(name: "duplicate_shape", arguments: ["shape_id": .string(headline.id.uuidString), "offset_x": 0, "offset_y": 100]))
        #expect(state.rows[0].shapes.last!.y == headline.y + 100)

        let rowCount = state.rows.count
        expectSuccess(await executor.call(name: "duplicate_row", arguments: ["row_id": rowId]))
        #expect(state.rows.count == rowCount + 1)
        #expect(state.rows[1].shapes.count == state.rows[0].shapes.count)

        let firstTemplate = state.rows[0].templates[0].id
        expectSuccess(await executor.call(name: "duplicate_template", arguments: ["row_id": rowId, "template_id": .string(firstTemplate.uuidString)]))
        #expect(state.rows[0].templates.count == columns + 1)
        expectSuccess(await executor.call(name: "move_template", arguments: ["row_id": rowId, "template_id": .string(firstTemplate.uuidString), "to_index": 2]))
        #expect(state.rows[0].templates[2].id == firstTemplate)
        let badIndex = await executor.call(name: "move_template", arguments: ["row_id": rowId, "template_id": .string(firstTemplate.uuidString), "to_index": 99])
        #expect(badIndex.isError == true)
    }

    @Test func replaceImageTargetsOneDeviceAndLocale() async throws {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }
        _ = await executor.call(name: "add_locale", arguments: ["code": "fr-FR"])
        _ = await executor.call(name: "add_shape", arguments: ["row_id": .string(state.rows[0].id.uuidString), "type": "device", "device_category": "iphone"])
        let device = state.rows[0].shapes.last!
        let image = try writeTestImage(tempDir)

        expectSuccess(await executor.call(name: "replace_image", arguments: [
            "shape_id": .string(device.id.uuidString), "image_path": .string(image.path), "locale": "fr-FR",
        ]))
        let updated = state.rows[0].shapes.last!
        #expect(updated.displayImageFileName != nil, "the first localized image seeds the base")
        #expect(state.localeState.override(forCode: "fr-FR", shapeId: device.id)?.overrideImageFileName != nil)

        _ = await executor.call(name: "add_shape", arguments: ["row_id": .string(state.rows[0].id.uuidString), "type": "star"])
        let notImage = await executor.call(name: "replace_image", arguments: [
            "shape_id": .string(state.rows[0].shapes.last!.id.uuidString), "image_path": .string(image.path),
        ])
        #expect(notImage.isError == true)
    }

    @Test func setAllDevicesAndArrange() async throws {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }
        let rowId = Value.string(state.rows[0].id.uuidString)
        _ = await executor.call(name: "add_shape", arguments: ["row_id": rowId, "type": "device", "template_index": 0])
        _ = await executor.call(name: "add_shape", arguments: ["row_id": rowId, "type": "device", "template_index": 1])
        let frame = try #require(DeviceFrameCatalog.allFrames.first { $0.fallbackCategory == .iphone && !$0.isLandscape && !$0.isModelBacked })

        expectSuccess(await executor.call(name: "set_all_devices", arguments: ["row_id": rowId, "device_frame_id": .string(frame.id)]))
        let devices = state.rows[0].shapes.filter { $0.type == .device }
        #expect(!devices.isEmpty)
        #expect(devices.allSatisfy { $0.deviceFrameId == frame.id })

        _ = await executor.call(name: "add_shape", arguments: ["row_id": rowId, "type": "rectangle", "x": 100, "y": 300])
        _ = await executor.call(name: "add_shape", arguments: ["row_id": rowId, "type": "circle", "x": 400, "y": 900])
        let pair = state.rows[0].shapes.suffix(2).map { Value.string($0.id.uuidString) }
        expectSuccess(await executor.call(name: "arrange_shapes", arguments: ["shape_ids": .array(pair), "action": "align_left"]))
        #expect(state.rows[0].shapes.suffix(2).allSatisfy { $0.x == 100 })
        let tooFew = await executor.call(name: "arrange_shapes", arguments: ["shape_ids": .array(pair), "action": "distribute_horizontally"])
        #expect(tooFew.isError == true)
    }

    @Test func localeLayoutAndBaseLocale() async throws {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }
        _ = await executor.call(name: "add_locale", arguments: ["code": "de-DE"])
        _ = await executor.call(name: "add_shape", arguments: ["row_id": .string(state.rows[0].id.uuidString), "type": "text", "text": "Hello", "width": 400])
        let shape = state.rows[0].shapes.last!
        let shapeId = Value.string(shape.id.uuidString)
        _ = await executor.call(name: "set_translation", arguments: ["shape_id": shapeId, "locale_code": "de-DE", "text": "Hallo", "auto_fit": false])

        expectSuccess(await executor.call(name: "set_locale_layout", arguments: ["shape_id": shapeId, "locale_code": "de-DE", "width": 600]))
        #expect(state.rows[0].shapes.last!.width == 400, "the base layout is untouched")
        let german = LocaleService.resolveShape(state.rows[0].shapes.last!, localeCode: "de-DE", localeState: state.localeState)
        #expect(german.width == 600)

        expectSuccess(await executor.call(name: "set_locale_layout", arguments: ["shape_id": shapeId, "locale_code": "de-DE", "reset": true]))
        let reset = LocaleService.resolveShape(state.rows[0].shapes.last!, localeCode: "de-DE", localeState: state.localeState)
        #expect(reset.width == 400)
        #expect(reset.text == "Hallo", "reset keeps the translation")

        expectSuccess(await executor.call(name: "set_base_locale", arguments: ["code": "de-DE"]))
        #expect(state.localeState.baseLocaleCode == "de-DE")
        #expect(state.rows[0].shapes.last!.text == "Hallo")
    }

    // MARK: - Project binding
    //
    // In this suite rather than their own: they share `SCREENSHOT_DATA_DIR` and the demo-mode
    // flag with the tests above, and `.serialized` serializes within a suite, not between suites.

    private func decodeEnvelope(_ result: CallTool.Result) throws -> [String: Any] {
        guard case .text(let json, _, _) = result.content.first else {
            throw MCPToolError.failed("expected text content")
        }
        return try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    /// Leaves the editor on the first project and returns the id of a second, closed one.
    private func makeClosedProject(_ state: AppState) async throws -> (open: UUID, closed: UUID) {
        let openProjectId = try #require(state.activeProject?.id)
        state.createProject(name: "Closed App")
        let closedId = try #require(state.activeProject?.id)
        state.selectProject(openProjectId)
        await state.projectOpenTask?.value
        #expect(state.activeProjectId == openProjectId)
        return (openProjectId, closedId)
    }

    private func readProject(_ id: UUID) async throws -> ProjectDocument {
        ProjectDocument(try #require(await AppState.readProjectAfterQueuedWrites(id)?.data))
    }

    @Test func editsAClosedProjectOnDiskWithoutTouchingTheOpenOne() async throws {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }
        let (_, closedId) = try await makeClosedProject(state)
        let openRows = state.rows
        let canUndoBefore = state.undoManager?.canUndo ?? false
        let closedRowId = try await readProject(closedId).rows[0].id
        let projectId = Value.string(closedId.uuidString)

        let added = await executor.call(name: "add_shape", arguments: [
            "project_id": projectId,
            "row_id": .string(closedRowId.uuidString),
            "type": "text",
            "text": "Closed edit",
        ])
        expectSuccess(added)
        let shapeId = try #require(try await readProject(closedId).rows[0].shapes.first { $0.text == "Closed edit" }?.id)

        expectSuccess(await executor.call(name: "add_locale", arguments: ["project_id": projectId, "code": "de-DE"]))
        expectSuccess(await executor.call(name: "set_translation", arguments: [
            "project_id": projectId,
            "shape_id": .string(shapeId.uuidString),
            "locale_code": "de-DE",
            "text": "Geschlossen",
        ]))

        let saved = try await readProject(closedId)
        #expect(saved.localeState.hasLocale("de-DE"))
        #expect(saved.localeState.overrides["de-DE"]?[shapeId.uuidString]?.text == "Geschlossen")
        #expect(state.rows == openRows, "the open project must not change")
        #expect((state.undoManager?.canUndo ?? false) == canUndoBefore, "a closed project's edit is not an editor undo step")

        // Ids from one project don't resolve in another.
        let wrongProject = await executor.call(name: "update_shape", arguments: ["shape_id": .string(shapeId.uuidString), "x": 10])
        #expect(wrongProject.isError == true)
    }

    @Test func addShapeIsOneUndoStep() async throws {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }
        let shapeCount = state.rows[0].shapes.count
        expectSuccess(await executor.call(name: "add_shape", arguments: [
            "row_id": .string(state.rows[0].id.uuidString),
            "type": "text",
            "text": "One step",
            "font_size": 80,
            "color": "#FF0000",
        ]))
        #expect(state.rows[0].shapes.count == shapeCount + 1)
        state.undoManager?.undo()
        #expect(state.rows[0].shapes.count == shapeCount)
    }

    @Test func zOrderWorksOutsideTheSelectedRow() async throws {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }
        let rowId = Value.string(state.rows[0].id.uuidString)
        _ = await executor.call(name: "add_row", arguments: [:])
        state.selectRow(state.rows[1].id)
        expectSuccess(await executor.call(name: "add_shape", arguments: ["row_id": rowId, "type": "rectangle"]))
        expectSuccess(await executor.call(name: "add_shape", arguments: ["row_id": rowId, "type": "circle"]))
        let rectangle = try #require(state.rows[0].shapes.last { $0.type == .rectangle })

        expectSuccess(await executor.call(name: "update_shape", arguments: ["shape_id": .string(rectangle.id.uuidString), "z_order": "front"]))
        #expect(state.rows[0].shapes.last?.id == rectangle.id)
        expectSuccess(await executor.call(name: "update_shape", arguments: ["shape_id": .string(rectangle.id.uuidString), "z_order": "back"]))
        #expect(state.rows[0].shapes.first?.id == rectangle.id)
    }

    @Test func deletingALockedShapeIsAnError() async throws {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }
        _ = await executor.call(name: "add_shape", arguments: ["row_id": .string(state.rows[0].id.uuidString), "type": "rectangle"])
        let shapeId = Value.string(state.rows[0].shapes.last!.id.uuidString)
        expectSuccess(await executor.call(name: "update_shape", arguments: ["shape_id": shapeId, "locked": true]))
        let count = state.rows[0].shapes.count

        let refused = await executor.call(name: "delete_shape", arguments: ["shape_id": shapeId])
        #expect(refused.isError == true)
        #expect(state.rows[0].shapes.count == count)
    }

    @Test func importsScreenshotsIntoAClosedProject() async throws {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }
        let (_, closedId) = try await makeClosedProject(state)
        let closedRowId = try await readProject(closedId).rows[0].id

        let imageURL = tempDir.appendingPathComponent("shot.png")
        let image = NSImage(size: NSSize(width: 1290, height: 2796), flipped: false) { rect in
            NSColor.systemTeal.setFill()
            rect.fill()
            return true
        }
        try #require(ExportService.pngData(from: image)).write(to: imageURL)

        let result = await executor.call(name: "import_screenshots", arguments: [
            "project_id": .string(closedId.uuidString),
            "row_id": .string(closedRowId.uuidString),
            "paths": [.string(imageURL.path)],
        ])
        expectSuccess(result)

        let saved = try await readProject(closedId)
        let fileName = try #require(saved.rows[0].shapes.compactMap(\.displayImageFileName).first)
        let written = PersistenceService.resourcesDir(closedId).appendingPathComponent(fileName)
        #expect(FileManager.default.fileExists(atPath: written.path))
    }

    /// With no undo stack to bring it back, the file a closed project's edit replaced goes once the write lands.
    @Test func aClosedProjectEditDeletesTheImageItReplaced() async throws {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }
        let (_, closedId) = try await makeClosedProject(state)
        let closedRowId = try await readProject(closedId).rows[0].id
        let imageURL = tempDir.appendingPathComponent("shot.png")
        try #require(ExportService.pngData(from: makeTestImage(width: 1290, height: 2796))).write(to: imageURL)
        let importArgs: [String: Value] = [
            "project_id": .string(closedId.uuidString),
            "row_id": .string(closedRowId.uuidString),
            "paths": [.string(imageURL.path)],
        ]

        expectSuccess(await executor.call(name: "import_screenshots", arguments: importArgs))
        let first = try #require(try await readProject(closedId).rows[0].shapes.compactMap(\.displayImageFileName).first)
        expectSuccess(await executor.call(name: "import_screenshots", arguments: importArgs))
        let savedData = try #require(await AppState.readProjectAfterQueuedWrites(closedId)?.data)
        let second = try #require(ProjectDocument(savedData).rows[0].shapes.compactMap(\.displayImageFileName).first)

        #expect(first != second)
        let resources = PersistenceService.resourcesDir(closedId)
        #expect(!FileManager.default.fileExists(atPath: resources.appendingPathComponent(first).path))
        #expect(FileManager.default.fileExists(atPath: resources.appendingPathComponent(second).path))
        #expect(state.projects.first { $0.id == closedId }?.modifiedAt == savedData.modifiedAt, "the project card sorts by the write")
    }

    /// Both calls read the project before either saves; unserialized, the second save drops the first edit.
    @Test func concurrentEditsToAClosedProjectBothLand() async throws {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }
        let (_, closedId) = try await makeClosedProject(state)
        let closedRowId = try await readProject(closedId).rows[0].id
        func addText(_ text: String) async -> CallTool.Result {
            await executor.call(name: "add_shape", arguments: [
                "project_id": .string(closedId.uuidString),
                "row_id": .string(closedRowId.uuidString),
                "type": "text",
                "text": .string(text),
            ])
        }

        async let first = addText("First")
        async let second = addText("Second")
        expectSuccess(await first)
        expectSuccess(await second)

        let texts = Set(try await readProject(closedId).rows[0].shapes.compactMap(\.text))
        #expect(texts.isSuperset(of: ["First", "Second"]))
    }

    @Test func aClosedCheckoutRefusesToCommitOnceTheProjectIsOpened() async throws {
        let (_, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }
        let (_, closedId) = try await makeClosedProject(state)
        let checkout = try await ProjectCheckout.open(projectId: closedId, state: state)
        defer { checkout.dispose() }
        checkout.mutate("Edit") { $0.rows[0].label = "Agent" }

        state.selectProject(closedId)
        await state.projectOpenTask?.value

        #expect(throws: ProjectCheckoutError.self) { try checkout.commit() }
        #expect(state.rows[0].label != "Agent")
    }

    @Test func previewRendersTheNamedProjectNotTheOpenOne() async throws {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let credentials = AppStoreConnectCredentialsStore.shared
        let originalDemoMode = credentials.isDemoMode
        credentials.isDemoMode = true
        defer { credentials.isDemoMode = originalDemoMode }
        AppStoreConnectDemoData.shared.updateContext(localeCodes: [], rowSizes: [])

        let openProjectId = try #require(state.activeProject?.id)
        state.createProject(name: "Other App")
        let targetId = try #require(state.activeProject?.id)
        state.setASCAppId("demo-app-1", forProject: targetId)
        #expect(targetId != openProjectId)

        // Put the editor back on the *other* project, so a fallback to "active" would be wrong.
        state.selectProject(openProjectId)
        await state.projectOpenTask?.value
        #expect(state.activeProjectId == openProjectId)

        let executor = MCPToolExecutor(state: state, jobs: MCPJobStore())
        let result = await executor.call(
            name: "preview_app_store_screenshot_sync",
            arguments: ["project_id": .string(targetId.uuidString), "mode": .string("sync")]
        )
        #expect(result.isError != true, "unexpected error: \(result.content)")

        let envelope = try decodeEnvelope(result)
        let payload = try #require(envelope["result"] as? [String: Any])
        #expect(payload["project_id"] as? String == targetId.uuidString)
        #expect(payload["project_name"] as? String == "Other App")
        #expect(state.activeProjectId == openProjectId, "a read must not move the editor")
    }

    @Test func previewWithoutAProjectIdIsRejectedRatherThanGuessing() async throws {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let credentials = AppStoreConnectCredentialsStore.shared
        let originalDemoMode = credentials.isDemoMode
        credentials.isDemoMode = true
        defer { credentials.isDemoMode = originalDemoMode }

        let executor = MCPToolExecutor(state: state, jobs: MCPJobStore())
        let result = await executor.call(name: "preview_app_store_screenshot_sync", arguments: [:])
        #expect(result.isError == true, "an omitted project_id must fail, not fall back to the open project")
    }

    @Test func anUnknownProjectIdIsAClientError() async throws {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let credentials = AppStoreConnectCredentialsStore.shared
        let originalDemoMode = credentials.isDemoMode
        credentials.isDemoMode = true
        defer { credentials.isDemoMode = originalDemoMode }

        let executor = MCPToolExecutor(state: state, jobs: MCPJobStore())
        let result = await executor.call(
            name: "preview_app_store_screenshot_sync",
            arguments: ["project_id": .string(UUID().uuidString)]
        )
        #expect(result.isError == true)
    }

    /// A successful apply discards its plan, and the documented recovery is to reissue the
    /// identical call. Demanding a project_id at that point would break the one path that is
    /// guaranteed safe.
    @Test func applyWithNoPlanAndNoProjectIdResolvesToNoCheckout() async throws {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let executor = MCPToolExecutor(state: state, jobs: MCPJobStore())
        let checkout = try await executor.optionalCheckout(MCPArguments(nil), matching: nil)
        #expect(checkout == nil)
    }

    @Test func applyRejectsAProjectIdThatDisagreesWithThePlan() async throws {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let executor = MCPToolExecutor(state: state, jobs: MCPJobStore())
        let plan = ASCScreenshotSyncPlan(
            id: "plan-1",
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(900),
            projectId: UUID(),
            projectModifiedAt: nil,
            appId: "123",
            sets: [],
            issues: [],
            directory: URL(fileURLWithPath: "/tmp")
        )
        await #expect(throws: MCPToolError.self) {
            _ = try await executor.optionalCheckout(
                MCPArguments(["project_id": .string(UUID().uuidString)]),
                matching: plan
            )
        }
    }

    /// A checkout of a project the editor does not have open must read that project's own rows.
    @Test func checkoutOfAClosedProjectReadsItsOwnRows() async throws {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }

        let firstId = try #require(state.activeProject?.id)
        let firstRowId = try #require(state.rows.first?.id)
        state.createProject(name: "Second")
        let secondId = try #require(state.activeProject?.id)
        state.addRow()
        state.saveAll()
        let secondRowIds = Set(state.rows.map(\.id))

        state.selectProject(firstId)
        await state.projectOpenTask?.value

        let checkout = try await ProjectCheckout.open(projectId: secondId, state: state)
        defer { checkout.dispose() }
        #expect(checkout.projectId == secondId)
        #expect(Set(checkout.rows.map(\.id)) == secondRowIds)
        #expect(!checkout.rows.contains { $0.id == firstRowId })
        #expect(state.activeProjectId == firstId, "opening a checkout must not move the editor")
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

        // The project is named explicitly: the app window's open project is no longer a default.
        let metaResult = await executor.call(
            name: "get_app_store_metadata",
            arguments: ["project_id": .string(projectId.uuidString)]
        )
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
            arguments: ["project_id": .string(projectId.uuidString), "descriptions": descriptions]
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

    // MARK: - Store metadata, Play, export options

    @Test func appStoreMetadataFieldsInDemoMode() async throws {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }
        let credentials = AppStoreConnectCredentialsStore.shared
        let originalDemoMode = credentials.isDemoMode
        credentials.isDemoMode = true
        defer { credentials.isDemoMode = originalDemoMode }
        AppStoreConnectDemoData.shared.updateContext(localeCodes: ["fr-FR"], rowSizes: [])
        let projectId = Value.string(try #require(state.activeProject?.id).uuidString)

        let apps = try decodeEnvelope(await executor.call(name: "list_app_store_apps", arguments: [:]))
        let appId = try #require((apps["apps"] as? [[String: Any]])?.first?["id"] as? String)
        expectSuccess(await executor.call(name: "link_project_stores", arguments: [
            "project_id": projectId, "app_id": .string(appId), "play_package_name": "com.example.shots",
        ]))
        #expect(state.activeProject?.ascAppId == appId)
        #expect(state.activeProject?.googlePlayPackageName == "com.example.shots")
        let badPackage = await executor.call(name: "link_project_stores", arguments: ["project_id": projectId, "play_package_name": "not a package"])
        #expect(badPackage.isError == true)

        let tooLong = await executor.call(name: "update_app_store_metadata", arguments: [
            "project_id": projectId,
            "locales": [["locale": "en-US", "keywords": .string(String(repeating: "k", count: 101))]],
        ])
        #expect(tooLong.isError == true)
        #expect("\(tooLong.content)".contains("100"))

        let updated = try decodeEnvelope(await executor.call(name: "update_app_store_metadata", arguments: [
            "project_id": projectId,
            "locales": [["locale": "en-US", "keywords": "screenshots,mockups", "promotional_text": "Now with MCP"]],
        ]))
        let version = try #require((updated["versions"] as? [[String: Any]])?.first)
        #expect(version["updated"] as? [String] == ["en-US"])
    }

    @Test func playUploadPlansAndRequiresConfirmation() async throws {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }
        let play = GooglePlayCredentialsStore.shared
        let originalDemoMode = play.isDemoMode
        play.isDemoMode = true
        defer { play.isDemoMode = originalDemoMode }
        let projectId = Value.string(try #require(state.activeProject?.id).uuidString)

        let plan = try decodeEnvelope(await executor.call(name: "preview_play_upload", arguments: [
            "project_id": projectId, "package_name": "com.example.shots", "image_type": "phoneScreenshots",
        ]))
        let rows = try #require(plan["rows"] as? [[String: Any]])
        #expect(rows.count == state.rows.count)
        #expect(rows.allSatisfy { $0["image_type"] as? String == "phoneScreenshots" })

        let unconfirmed = await executor.call(name: "upload_play_screenshots", arguments: ["project_id": projectId, "confirm": false])
        #expect(unconfirmed.isError == true)
    }

    @Test func exportContinuousRowsForChosenRows() async throws {
        let (executor, state, tempDir) = makeExecutor()
        defer { cleanupTestState(tempDir) }
        _ = await executor.call(name: "add_row", arguments: [:])
        let projectId = Value.string(try #require(state.activeProject?.id).uuidString)

        let result = try decodeEnvelope(await executor.call(name: "export_project", arguments: [
            "project_id": projectId,
            "row_ids": [.string(state.rows[0].id.uuidString)],
            "layout": "continuous",
        ]))
        let files = try #require(result["files"] as? [String])
        #expect(files.count == 1)
        let image = try #require(NSImage(contentsOfFile: files[0]))
        #expect(image.size.width > image.size.height, "a stitched row is wider than tall")
    }
}
