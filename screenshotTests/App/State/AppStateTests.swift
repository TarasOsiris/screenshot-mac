import AppKit
import CoreGraphics
@testable import Screenshot_Bro
import SwiftUI
import Testing

@Suite(.serialized)
@MainActor
struct AppStateTests {

    func makeState(fonts: CustomFontLibrary = CustomFontLibrary()) -> (AppState, URL) { makeTestState(fonts: fonts) }
    func cleanup(_ tempDir: URL) { cleanupTestState(tempDir) }
    func bundledFontURL(_ fileName: String) throws -> URL {
        try #require(TemplateService.sharedFontsURL).appendingPathComponent(fileName)
    }

    // MARK: - Initial state

    @Test func firstLaunchHasNoProjectOrRows() {
        let (state, tempDir) = makeEmptyTestState()
        defer { cleanup(tempDir) }
        #expect(state.visibleProjects.isEmpty)
        #expect(state.activeProjectId == nil)
        #expect(state.rows.isEmpty)
    }

    @Test func initialRowKeepsGenericDefaultWhenNoFrameIsStored() throws {
        let defaults = UserDefaults.standard
        let previousCategory = defaults.object(forKey: AppSettingsKeys.defaultDeviceCategory)
        let previousFrameId = defaults.object(forKey: AppSettingsKeys.defaultDeviceFrameId)
        defer {
            if let previousCategory {
                defaults.set(previousCategory, forKey: AppSettingsKeys.defaultDeviceCategory)
            } else {
                defaults.removeObject(forKey: AppSettingsKeys.defaultDeviceCategory)
            }
            if let previousFrameId {
                defaults.set(previousFrameId, forKey: AppSettingsKeys.defaultDeviceFrameId)
            } else {
                defaults.removeObject(forKey: AppSettingsKeys.defaultDeviceFrameId)
            }
        }

        defaults.set(DeviceCategory.iphone.rawValue, forKey: AppSettingsKeys.defaultDeviceCategory)
        defaults.set("", forKey: AppSettingsKeys.defaultDeviceFrameId)

        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        let row = state.rows[0]
        #expect(row.defaultDeviceCategory == .iphone)
        #expect(row.defaultDeviceFrameId == nil)

        let device = try #require(row.shapes.first(where: { $0.type == .device }))
        #expect(device.deviceCategory == .iphone)
        #expect(device.deviceFrameId == nil)
    }

    // MARK: - Row operations

    @Test func addRowIncreasesCount() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let initialCount = state.rows.count
        state.addRow()
        #expect(state.rows.count == initialCount + 1)
        #expect(state.selectedRowId == state.rows.last?.id, "New row should be selected")
    }

    @Test func deleteRowRequiresAtLeastOne() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let onlyRowId = state.rows.first!.id
        state.deleteRow(onlyRowId)
        #expect(state.rows.count == 1, "Cannot delete last row")
    }

    @Test func deleteRowRemovesAndSelectsAdjacent() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        state.addRow()
        state.addRow()
        #expect(state.rows.count == 3)

        let middleRowId = state.rows[1].id
        state.selectRow(middleRowId)
        state.deleteRow(middleRowId)

        #expect(state.rows.count == 2)
        #expect(!state.rows.contains { $0.id == middleRowId })
        #expect(state.selectedRowId != nil, "Should auto-select another row")
    }

    @Test func duplicateRowCopiesProperties() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let sourceId = state.rows.first!.id
        state.selectRow(sourceId)

        // Add a shape to the source row
        state.addShape(CanvasShapeModel.defaultRectangle(centerX: 621, centerY: 1344))

        state.duplicateRow(sourceId)
        #expect(state.rows.count == 2)

        let copy = state.rows[1]
        let source = state.rows[0]
        #expect(copy.templateWidth == source.templateWidth)
        #expect(copy.templateHeight == source.templateHeight)
        #expect(copy.shapes.count == source.shapes.count)
        #expect(copy.label == "\(source.label) copy")
        // Shapes should have different IDs
        #expect(copy.shapes.first?.id != source.shapes.first?.id)
    }

    @Test func moveRowUpAndDown() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        state.addRow()
        let firstId = state.rows[0].id
        let secondId = state.rows[1].id

        state.moveRowDown(firstId)
        #expect(state.rows[0].id == secondId)
        #expect(state.rows[1].id == firstId)

        state.moveRowUp(firstId)
        #expect(state.rows[0].id == firstId)
        #expect(state.rows[1].id == secondId)
    }

    @Test func moveRowUpAtTopIsNoOp() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        state.addRow()
        let firstId = state.rows[0].id
        state.moveRowUp(firstId)
        #expect(state.rows[0].id == firstId, "Already at top, no change")
    }

    @Test func resizeRowScalesShapes() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        state.selectRow(state.rows.first!.id)
        state.addShape(CanvasShapeModel(type: .rectangle, x: 100, y: 200, width: 300, height: 400))

        let originalWidth = state.rows[0].templateWidth
        let originalHeight = state.rows[0].templateHeight
        let newWidth = originalWidth * 2
        let newHeight = originalHeight * 2

        state.resizeRow(at: 0, newWidth: newWidth, newHeight: newHeight)

        #expect(state.rows[0].templateWidth == newWidth)
        #expect(state.rows[0].templateHeight == newHeight)

        let shape = state.rows[0].shapes.first { $0.type == .rectangle }!
        #expect(abs(shape.x - 200) < 0.01, "X should scale by 2x")
        #expect(abs(shape.y - 400) < 0.01, "Y should scale by 2x")
        #expect(abs(shape.width - 600) < 0.01, "Width should scale by 2x")
        #expect(abs(shape.height - 800) < 0.01, "Height should scale by 2x")
    }

    @Test func updateRowLabelSetsManualFlag() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let rowId = state.rows.first!.id
        state.updateRowLabel(rowId, text: "Custom Label")
        #expect(state.rows[0].label == "Custom Label")
        #expect(state.rows[0].isLabelManuallySet == true)
    }

    @Test func updateRowLabelEmptyResetsToPreset() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let rowId = state.rows.first!.id
        state.updateRowLabel(rowId, text: "Custom")
        state.updateRowLabel(rowId, text: "  ")
        #expect(state.rows[0].isLabelManuallySet == false)
    }

    @Test func continuousRowEditComposesPendingBackgroundChanges() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let rowId = state.rows[0].id
        state.edits.rowEditThrottle.markRecentApply()

        var firstConfig = state.rows[0].gradientConfig
        firstConfig.centerX = 0.25
        state.updateRowContinuous(rowId) { $0.gradientConfig = firstConfig }

        var secondConfig = try #require(state.edits.continuousRowEditWorkingRow).gradientConfig
        secondConfig.centerY = 0.75
        state.updateRowContinuous(rowId) { $0.gradientConfig = secondConfig }

        state.flushPendingContinuousRowEdit()
        #expect(state.rows[0].gradientConfig.centerX == 0.25)
        #expect(state.rows[0].gradientConfig.centerY == 0.75)

        state.finishContinuousRowEditIfNeeded()
    }

    // MARK: - Shape operations

    @Test func addShapeAppendsAndSelects() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        state.selectRow(state.rows.first!.id)
        let shape = CanvasShapeModel.defaultRectangle(centerX: 621, centerY: 1344)
        state.addShape(shape)

        let row = state.rows.first!
        #expect(row.shapes.contains { $0.id == shape.id })
        #expect(state.selectedShapeId == shape.id)
    }

    @Test func addShapeRequiresSelectedRow() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        state.deselectAll()
        let shape = CanvasShapeModel.defaultRectangle(centerX: 621, centerY: 1344)
        let countBefore = state.rows.first!.shapes.count
        state.addShape(shape)
        #expect(state.rows.first!.shapes.count == countBefore, "No row selected, shape not added")
    }

    @Test func deleteShapeClearsSelection() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        state.selectRow(state.rows.first!.id)
        let shape = CanvasShapeModel.defaultRectangle(centerX: 621, centerY: 1344)
        state.addShape(shape)
        #expect(state.selectedShapeId == shape.id)

        state.deleteShape(shape.id)
        #expect(state.selectedShapeId == nil)
        #expect(!state.rows.first!.shapes.contains { $0.id == shape.id })
    }

    // MARK: - Replace SVG

    static let squareSvg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><rect width="100" height="100"/></svg>"#
    static let squareSvgSize = CGSize(width: 100, height: 100)
    static let wideSvg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 100"><rect width="200" height="100"/></svg>"#
    static let wideSvgSize = CGSize(width: 200, height: 100)

    func addStyledSvgShape(to state: AppState) -> CanvasShapeModel {
        state.selectRow(state.rows.first!.id)
        var shape = CanvasShapeModel.defaultSvg(
            centerX: 600, centerY: 1000, svgContent: Self.squareSvg, size: CGSize(width: 400, height: 400)
        )
        shape.rotation = 30
        shape.opacity = 0.6
        shape.shadow = ShadowConfig(enabled: true, radius: 20)
        shape.outlineColor = .blue
        shape.outlineWidth = 4
        shape.clipToTemplate = true
        shape.svgUseColor = true
        shape.color = .red
        state.addShape(shape)
        return state.rows.first!.shapes.first { $0.id == shape.id }!
    }

    @Test func replaceSvgKeepsEveryPropertyButArtworkAndFrame() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let original = addStyledSvgShape(to: state)

        state.replaceSvg(
            shapeId: original.id, content: Self.wideSvg, naturalSize: Self.wideSvgSize,
            useColor: true, color: original.color
        )

        var expected = original
        expected.svgContent = Self.wideSvg
        expected.fitFrame(toAspectOf: Self.wideSvgSize)
        #expect(expected.height == 200, "The fixture must actually reshape the frame")
        #expect(state.rows.first!.shapes.first { $0.id == original.id } == expected, "Only the artwork and its frame change")
    }

    @Test func replaceSvgAppliesColorChosenInDialog() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let original = addStyledSvgShape(to: state)

        state.replaceSvg(
            shapeId: original.id, content: Self.wideSvg, naturalSize: Self.wideSvgSize,
            useColor: false, color: .green
        )

        let replaced = state.rows.first!.shapes.first { $0.id == original.id }!
        #expect(replaced.svgUseColor == false)
        #expect(replaced.colorData == original.colorData, "The color is kept for when the override is turned back on")
    }

    @Test func replaceSvgUndoesAsOneStep() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let original = addStyledSvgShape(to: state)
        let um = state.undoManager!
        um.removeAllActions()

        state.replaceSvg(
            shapeId: original.id, content: Self.wideSvg, naturalSize: Self.wideSvgSize,
            useColor: true, color: original.color
        )
        #expect(um.canUndo)

        um.undo()
        #expect(state.rows.first!.shapes.first { $0.id == original.id } == original)
        #expect(!um.canUndo)
    }

    @Test func replaceSvgWithSameArtworkRegistersNoUndoStep() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let original = addStyledSvgShape(to: state)
        let um = state.undoManager!
        um.removeAllActions()

        state.replaceSvg(
            shapeId: original.id, content: Self.squareSvg, naturalSize: Self.squareSvgSize,
            useColor: true, color: original.color
        )
        #expect(!um.canUndo)
        #expect(state.rows.first!.shapes.first { $0.id == original.id } == original)
    }

    @Test func bringShapeToFrontMovesToEnd() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        state.selectRow(state.rows.first!.id)

        let s1 = CanvasShapeModel(id: UUID(), type: .rectangle, x: 0, y: 0)
        let s2 = CanvasShapeModel(id: UUID(), type: .rectangle, x: 100, y: 100)
        let s3 = CanvasShapeModel(id: UUID(), type: .rectangle, x: 200, y: 200)
        state.addShape(s1)
        state.addShape(s2)
        state.addShape(s3)

        // s1 is at index 0 (could also be at different index due to default device)
        state.selectShape(s1.id, in: state.rows.first!.id)
        state.bringShapeToFront(s1.id)

        let shapes = state.rows.first!.shapes
        #expect(shapes.last?.id == s1.id, "s1 should be at the end (front)")
    }

    @Test func sendShapeToBackMovesToStart() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        state.selectRow(state.rows.first!.id)

        let s1 = CanvasShapeModel(id: UUID(), type: .rectangle, x: 0, y: 0)
        let s2 = CanvasShapeModel(id: UUID(), type: .rectangle, x: 100, y: 100)
        state.addShape(s1)
        state.addShape(s2)

        state.selectShape(s2.id, in: state.rows.first!.id)
        state.sendShapeToBack(s2.id)

        let shapes = state.rows.first!.shapes
        #expect(shapes.first?.id == s2.id, "s2 should be at the start (back)")
    }

    // MARK: - Zoom

    // These used to reimplement the clamp in the test body and assert on their own arithmetic.
    // ZoomController.level is now private(set), so they exercise the real methods instead.

    @Test func zoomInAndOut() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        state.zoom.set(1.0)
        state.zoom.zoomIn()
        #expect(state.zoom.level == 1.0 + ZoomConstants.step)
        state.zoom.zoomOut()
        #expect(state.zoom.level == 1.0)
    }

    @Test func zoomClampsToRange() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        state.zoom.set(ZoomConstants.max)
        state.zoom.zoomIn()
        #expect(state.zoom.level == ZoomConstants.max, "Cannot exceed max")

        state.zoom.set(ZoomConstants.min)
        state.zoom.zoomOut()
        #expect(state.zoom.level == ZoomConstants.min, "Cannot go below min")

        // Out-of-range values are clamped rather than rejected.
        state.zoom.set(99)
        #expect(state.zoom.level == ZoomConstants.max)
        state.zoom.set(-5)
        #expect(state.zoom.level == ZoomConstants.min)
    }
}
