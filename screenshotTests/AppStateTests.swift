import Testing
import AppKit
@testable import Screenshot_Bro

@Suite(.serialized)
@MainActor
struct AppStateTests {

    private func makeState() -> (AppState, URL) { makeTestState() }
    private func cleanup(_ tempDir: URL) { cleanupTestState(tempDir) }

    // MARK: - Initial state

    @Test func initialStateHasOneProjectAndOneRow() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        #expect(state.projects.count == 1)
        #expect(state.rows.count == 1)
        #expect(state.activeProjectId != nil)
        #expect(state.selectedRowId == state.rows.first?.id)
    }

    @Test func initialRowKeepsGenericDefaultWhenNoFrameIsStored() throws {
        let defaults = UserDefaults.standard
        let previousCategory = defaults.object(forKey: "defaultDeviceCategory")
        let previousFrameId = defaults.object(forKey: "defaultDeviceFrameId")
        defer {
            if let previousCategory {
                defaults.set(previousCategory, forKey: "defaultDeviceCategory")
            } else {
                defaults.removeObject(forKey: "defaultDeviceCategory")
            }
            if let previousFrameId {
                defaults.set(previousFrameId, forKey: "defaultDeviceFrameId")
            } else {
                defaults.removeObject(forKey: "defaultDeviceFrameId")
            }
        }

        defaults.set(DeviceCategory.iphone.rawValue, forKey: "defaultDeviceCategory")
        defaults.set("", forKey: "defaultDeviceFrameId")

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

    @Test func batchImportImagesReusesExistingDeviceShapes() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        let rowId = try #require(state.rows.first?.id)
        let originalDevices = state.rows[0].shapes.filter { $0.type == .device }
        #expect(originalDevices.count == state.rows[0].templates.count)

        let images = (0..<state.rows[0].templates.count).map { _ in
            makeTestImage(width: 1206, height: 2622)
        }

        state.batchImportImages(images, into: rowId)

        let row = state.rows[0]
        let devices = row.shapes.filter { $0.type == .device }
        #expect(devices.count == originalDevices.count)
        #expect(Set(devices.map(\.id)) == Set(originalDevices.map(\.id)))
        #expect(devices.allSatisfy { $0.screenshotFileName != nil })
        #expect(row.shapes.filter { $0.type == .image }.isEmpty)
    }

    @Test func batchImportImagesCreatesMissingDeviceUsingMostCommonRowFrame() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        let commonFrameId = try #require(DeviceFrameCatalog.firstPortraitFrameId(for: .iphone))
        let commonFrame = try #require(DeviceFrameCatalog.frame(for: commonFrameId))
        let alternateFrame = try #require(
            DeviceFrameCatalog.allFrames.first {
                $0.fallbackCategory == .iphone && !$0.isLandscape && $0.id != commonFrameId
            }
        )

        var row = state.rows[0]
        row.defaultDeviceFrameId = alternateFrame.id
        row.shapes = [
            makeDevice(in: row, templateIndex: 0, frame: commonFrame),
            makeDevice(in: row, templateIndex: 1, frame: commonFrame)
        ]
        state.rows[0] = row
        state.selectRow(row.id)

        let images = [
            makeTestImage(width: 1206, height: 2622),
            makeTestImage(width: 1206, height: 2622),
            makeTestImage(width: 1206, height: 2622)
        ]

        state.batchImportImages(images, into: row.id)

        let updatedRow = state.rows[0]
        let devices = updatedRow.shapes.filter { $0.type == .device }
        #expect(devices.count == 3)

        let createdDevice = try #require(devices.first {
            updatedRow.owningTemplateIndex(for: $0) == 2
        })
        #expect(createdDevice.deviceFrameId == commonFrame.id)
        #expect(createdDevice.screenshotFileName != nil)
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

    // MARK: - Selection

    @Test func selectRowClearsShapeSelection() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        state.selectRow(state.rows.first!.id)
        let shape = CanvasShapeModel.defaultRectangle(centerX: 621, centerY: 1344)
        state.addShape(shape)
        #expect(state.selectedShapeId == shape.id)

        state.addRow()
        state.selectRow(state.rows.last!.id)
        #expect(state.selectedShapeId == nil, "Shape selection cleared when switching rows")
    }

    @Test func deselectAllClearsEverything() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        state.selectRow(state.rows.first!.id)
        state.addShape(CanvasShapeModel.defaultRectangle(centerX: 621, centerY: 1344))

        state.deselectAll()
        #expect(state.selectedRowId == nil)
        #expect(state.selectedShapeId == nil)
    }

    @Test func selectShapeAlsoSelectsRow() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        state.addRow()
        let row2Id = state.rows[1].id
        state.selectRow(row2Id)
        let shape = CanvasShapeModel.defaultRectangle(centerX: 621, centerY: 1344)
        state.addShape(shape)

        // Select a shape in row 2 while row 1 is selected
        state.selectRow(state.rows[0].id)
        state.selectShape(shape.id, in: row2Id)
        #expect(state.selectedRowId == row2Id)
        #expect(state.selectedShapeId == shape.id)
    }

    // MARK: - Template operations

    @Test func addTemplateIncreasesCount() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let rowId = state.rows.first!.id
        let initialCount = state.rows.first!.templates.count
        state.addTemplate(to: rowId)
        #expect(state.rows.first!.templates.count == initialCount + 1)
    }

    @Test func removeTemplateDecreasesCount() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let rowId = state.rows.first!.id
        state.addTemplate(to: rowId)
        let countAfterAdd = state.rows.first!.templates.count
        let templateId = try #require(state.rows.first!.templates.last?.id)
        state.removeTemplate(templateId, from: rowId)
        #expect(state.rows.first!.templates.count == countAfterAdd - 1)
    }

    // MARK: - Locale operations via AppState

    @Test func addLocaleUpdatesState() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        #expect(state.localeState.locales.count == 1)
        state.addLocale(.init(code: "fr", label: "French"))
        #expect(state.localeState.locales.count == 2)
        #expect(state.localeState.locales.last?.code == "fr")
    }

    @Test func cycleLocaleForwardAndBackward() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        state.addLocale(.init(code: "fr", label: "French"))
        state.addLocale(.init(code: "de", label: "German"))
        // addLocale sets active to the newly added locale
        state.setActiveLocale("en")
        #expect(state.localeState.activeLocaleCode == "en")

        state.cycleLocaleForward()
        #expect(state.localeState.activeLocaleCode == "fr")

        state.cycleLocaleForward()
        #expect(state.localeState.activeLocaleCode == "de")

        state.cycleLocaleForward()
        #expect(state.localeState.activeLocaleCode == "en", "Should wrap around")

        state.cycleLocaleBackward()
        #expect(state.localeState.activeLocaleCode == "de", "Should wrap backward")
    }

    @Test func translateShapesUsesRequestedLocaleForMissingCheck() async {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        state.addLocale(.init(code: "fr", label: "French"))
        state.addLocale(.init(code: "de", label: "German"))
        state.selectRow(state.rows.first!.id)

        var shape = CanvasShapeModel.defaultText(centerX: 621, centerY: 1344)
        shape.text = "Hello"
        state.addShape(shape)

        state.updateTranslationText(shapeId: shape.id, localeCode: "de", text: "Hallo")
        state.setActiveLocale("de")

        await translateShapes(
            state: state,
            targetLocaleCode: "fr",
            onlyUntranslated: true
        ) { _ in
            "Bonjour"
        }

        #expect(state.localeState.override(forCode: "fr", shapeId: shape.id)?.text == "Bonjour")
        #expect(state.localeState.override(forCode: "de", shapeId: shape.id)?.text == "Hallo")
    }

    @Test func translateShapesWritesToRequestedLocaleEvenIfActiveLocaleChanges() async {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        state.addLocale(.init(code: "fr", label: "French"))
        state.addLocale(.init(code: "de", label: "German"))
        state.selectRow(state.rows.first!.id)
        state.setActiveLocale("fr")

        var shape = CanvasShapeModel.defaultText(centerX: 621, centerY: 1344)
        shape.text = "Hello"
        state.addShape(shape)

        await translateShapes(
            state: state,
            targetLocaleCode: "fr",
            onlyUntranslated: false
        ) { text in
            state.setActiveLocale("de")
            return "\(text)-fr"
        }

        #expect(state.localeState.activeLocaleCode == "de")
        #expect(state.localeState.override(forCode: "fr", shapeId: shape.id)?.text == "Hello-fr")
        #expect(state.localeState.override(forCode: "de", shapeId: shape.id)?.text == nil)
    }

    // MARK: - Zoom

    @Test func zoomInAndOut() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let initial = state.zoomLevel
        state.zoomLevel = 1.0
        state.zoomLevel = min(ZoomConstants.max, state.zoomLevel + ZoomConstants.step)
        #expect(state.zoomLevel == 1.25)
        state.zoomLevel = max(ZoomConstants.min, state.zoomLevel - ZoomConstants.step)
        #expect(state.zoomLevel == 1.0)
    }

    @Test func zoomClampsToRange() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        state.zoomLevel = ZoomConstants.max
        state.zoomLevel = min(ZoomConstants.max, state.zoomLevel + ZoomConstants.step)
        #expect(state.zoomLevel == ZoomConstants.max, "Cannot exceed max")

        state.zoomLevel = ZoomConstants.min
        state.zoomLevel = max(ZoomConstants.min, state.zoomLevel - ZoomConstants.step)
        #expect(state.zoomLevel == ZoomConstants.min, "Cannot go below min")
    }

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

        state.saveImage(makeTestImage(width: 1200, height: 2600), for: shapeId)

        let shape = try #require(state.rows.first?.shapes.first(where: { $0.id == shapeId }))
        #expect(shape.displayImageFileName == nil)
        #expect(state.screenshotImages.isEmpty)
        #expect(state.saveError?.contains("Disk full") == true)
    }

    // MARK: - Nudge

    @Test func nudgeSelectedShapeMovesPosition() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        state.selectRow(state.rows.first!.id)
        let shape = CanvasShapeModel(type: .rectangle, x: 100, y: 200, width: 50, height: 50)
        state.addShape(shape)

        state.nudgeSelectedShapes(dx: 10, dy: -5)

        let updated = state.rows.first!.shapes.first { $0.id == shape.id }!
        #expect(updated.x == 110)
        #expect(updated.y == 195)
    }

    @Test func discreteShapeUpdateFlushesPendingContinuousEdit() async throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        state.selectRow(state.rows.first!.id)
        var shape = CanvasShapeModel.defaultRectangle(centerX: 621, centerY: 1344)
        shape.opacity = 0.8
        state.addShape(shape)

        var continuous = try #require(state.rows.first?.shapes.first(where: { $0.id == shape.id }))
        continuous.borderRadius = 40
        state.updateShapeContinuous(continuous)

        continuous.borderRadius = 120
        state.updateShapeContinuous(continuous)

        var discrete = try #require(state.rows.first?.shapes.first(where: { $0.id == shape.id }))
        discrete.opacity = 0.35
        state.updateShape(discrete)

        try await Task.sleep(for: .milliseconds(700))

        let updated = try #require(state.rows.first?.shapes.first(where: { $0.id == shape.id }))
        #expect(updated.borderRadius == 120)
        #expect(updated.opacity == 0.35)
        #expect(state.continuousEditPending == nil)
        #expect(state.continuousEditShapeId == nil)
    }

    @Test func selectionChangeFlushesPendingContinuousEdit() async throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        state.selectRow(state.rows.first!.id)
        let rect = CanvasShapeModel.defaultRectangle(centerX: 400, centerY: 700)
        let text = CanvasShapeModel.defaultText(centerX: 800, centerY: 700)
        state.addShape(rect)
        state.addShape(text)

        state.selectShape(rect.id, in: state.rows[0].id)

        var pendingRect = try #require(state.rows[0].shapes.first(where: { $0.id == rect.id }))
        pendingRect.borderRadius = 20
        state.updateShapeContinuous(pendingRect)

        pendingRect.borderRadius = 90
        state.updateShapeContinuous(pendingRect)

        state.selectShape(text.id, in: state.rows[0].id)
        try await Task.sleep(for: .milliseconds(700))

        let updatedRect = try #require(state.rows[0].shapes.first(where: { $0.id == rect.id }))
        #expect(updatedRect.borderRadius == 90)
        #expect(state.selectedShapeId == text.id)
        #expect(state.continuousEditPending == nil)
        #expect(state.continuousEditShapeId == nil)
    }

    // MARK: - Project operations

    @Test func createProjectSwitchesToNew() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let initialId = state.activeProjectId
        state.createProject(name: "New Project")
        #expect(state.projects.count == 2)
        #expect(state.activeProjectId != initialId)
        #expect(state.activeProject?.name == "New Project")
    }

    @Test func duplicateProjectSwitchesToCopy() async throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        let sourceId = try #require(state.activeProjectId)
        state.duplicateProject(sourceId)

        for _ in 0..<10 {
            if state.activeProject?.name.hasSuffix("Copy") == true {
                break
            }
            await Task.yield()
        }

        #expect(state.projects.count == 2)
        #expect(state.activeProject?.name.hasSuffix("Copy") == true)
    }

    @Test func renameProjectUpdatesName() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let projectId = try #require(state.activeProjectId)
        state.renameProject(projectId, to: "Renamed")
        #expect(state.activeProject?.name == "Renamed")
    }

    @Test func deleteProjectCreatesNewIfLast() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let projectId = state.activeProjectId!
        state.deleteProject(projectId)
        #expect(state.visibleProjects.count == 1, "Should create fallback project")
        #expect(state.activeProjectId != nil)
    }

    @Test func selectProjectSetsOpeningIndicatorUntilImagesFinishLoading() async throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        let originalProjectId = try #require(state.activeProjectId)
        // Explicitly add an image shape so the test doesn't depend on makeDefaultRow
        // creating device shapes (which can fail when tests run concurrently and
        // the shared SCREENSHOT_DATA_DIR env var races).
        state.selectRow(state.rows.first?.id)
        let imageShape = CanvasShapeModel.defaultImage(centerX: 500, centerY: 500)
        state.addShape(imageShape)
        let firstShapeId = imageShape.id
        state.saveImage(makeTestImage(width: 1200, height: 2600), for: firstShapeId)
        state.saveAll()

        state.createProject(name: "Second")
        state.selectProject(originalProjectId)

        #expect(state.isOpeningProject)

        for _ in 0..<50 {
            if !state.isOpeningProject {
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(!state.isOpeningProject)
        #expect(!state.screenshotImages.isEmpty)
    }

    private func makeDevice(in row: ScreenshotRow, templateIndex: Int, frame: DeviceFrame) -> CanvasShapeModel {
        let centerX = row.templateCenterX(at: templateIndex)
        let centerY = row.templateHeight / 2
        var device = CanvasShapeModel.defaultDevice(
            centerX: centerX,
            centerY: centerY,
            templateHeight: row.templateHeight,
            category: frame.fallbackCategory
        )
        device.selectRealFrame(frame)
        device.adjustToDeviceAspectRatio(centerX: centerX)
        return device
    }
}
