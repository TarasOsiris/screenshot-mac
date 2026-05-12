import Testing
import AppKit
@testable import Screenshot_Bro

@Suite(.serialized)
@MainActor
struct AppStateTests {

    private func makeState() -> (AppState, URL) { makeTestState() }
    private func cleanup(_ tempDir: URL) { cleanupTestState(tempDir) }
    private func bundledFontURL(_ fileName: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("screenshot/Templates.bundle/shared/fonts/\(fileName)")
    }

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

    @Test func batchImportImagesSkipsTemplatesWithoutDevices() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        let frameId = try #require(DeviceFrameCatalog.firstPortraitFrameId(for: .iphone))
        let frame = try #require(DeviceFrameCatalog.frame(for: frameId))

        var row = state.rows[0]
        while row.templates.count < 3 {
            state.appendTemplate(to: 0)
            row = state.rows[0]
        }
        row.shapes = [
            makeDevice(in: row, templateIndex: 0, frame: frame),
            makeDevice(in: row, templateIndex: 2, frame: frame)
        ]
        state.rows[0] = row
        state.selectRow(row.id)

        let images = [
            makeTestImage(width: 1206, height: 2622),
            makeTestImage(width: 1206, height: 2622)
        ]

        state.batchImportImages(images, into: row.id)

        let updatedRow = state.rows[0]
        #expect(updatedRow.templates.count == 3, "No new templates should be appended")

        let devices = updatedRow.shapes.filter { $0.type == .device }
        #expect(devices.count == 2, "No new devices should be added to template 1")
        #expect(devices.allSatisfy { $0.screenshotFileName != nil })

        let deviceTemplateIndices = Set(devices.compactMap { updatedRow.owningTemplateIndex(for: $0) })
        #expect(deviceTemplateIndices == [0, 2])
    }

    @Test func batchImportImagesAppendsTemplatesForOverflowImages() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        let frameId = try #require(DeviceFrameCatalog.firstPortraitFrameId(for: .iphone))
        let frame = try #require(DeviceFrameCatalog.frame(for: frameId))

        // Default row; keep only template 0 with a device — other default templates stay device-less.
        var row = state.rows[0]
        let initialTemplateCount = row.templates.count
        #expect(initialTemplateCount >= 1)
        row.shapes = [makeDevice(in: row, templateIndex: 0, frame: frame)]
        state.rows[0] = row
        state.selectRow(row.id)

        // One image fills template 0's existing device; remaining images overflow and append new templates.
        let overflowCount = initialTemplateCount
        let images = (0..<(1 + overflowCount)).map { _ in
            makeTestImage(width: 1206, height: 2622)
        }

        state.batchImportImages(images, into: row.id)

        let updatedRow = state.rows[0]
        #expect(updatedRow.templates.count == initialTemplateCount + overflowCount,
                "Overflow images should append new templates beyond the original ones")

        let devices = updatedRow.shapes.filter { $0.type == .device }
        #expect(devices.count == 1 + overflowCount,
                "One existing device + one new device per overflow image")
        #expect(devices.allSatisfy { $0.screenshotFileName != nil })

        let deviceTemplateIndices = Set(devices.compactMap { updatedRow.owningTemplateIndex(for: $0) })
        let expectedIndices = Set([0] + Array(initialTemplateCount..<updatedRow.templates.count))
        #expect(deviceTemplateIndices == expectedIndices,
                "Devices should only live in template 0 and in newly-appended overflow templates")
    }

    @Test func addImageShapeUsesAndroidPhoneWhenRowDefaultIsAndroidPhone() throws {
        // 1080x1920 is the iPhone 6/7/8 Plus exact size but also the most common Android phone
        // resolution — detection leans iPhone, so the row's Android Phone default must win.
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        var row = state.rows[0]
        row.defaultDeviceCategory = .androidPhone
        row.defaultDeviceFrameId = nil
        row.shapes = []
        state.rows[0] = row
        state.selectRow(row.id)

        let image = makeTestImage(width: 1080, height: 1920)
        state.addImageShape(image: image, centerX: row.templateCenterX(at: 0), centerY: row.templateHeight / 2)

        let added = try #require(state.rows[0].shapes.last)
        #expect(added.type == .device)
        #expect(added.deviceCategory == .androidPhone)
    }

    @Test func addImageShapeUsesAndroidTabletWhenRowDefaultIsAndroidTablet() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        var row = state.rows[0]
        row.defaultDeviceCategory = .androidTablet
        row.defaultDeviceFrameId = nil
        row.shapes = []
        state.rows[0] = row
        state.selectRow(row.id)

        let image = makeTestImage(width: 1800, height: 2400)
        state.addImageShape(image: image, centerX: row.templateCenterX(at: 0), centerY: row.templateHeight / 2)

        let added = try #require(state.rows[0].shapes.last)
        #expect(added.type == .device)
        #expect(added.deviceCategory == .androidTablet)
    }

    @Test func addImageShapeKeepsAppleDetectionWhenRowDefaultIsMismatchedShape() throws {
        // Phone-shaped image must not become Android Tablet just because that's the row default.
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        var row = state.rows[0]
        row.defaultDeviceCategory = .androidTablet
        row.defaultDeviceFrameId = nil
        row.shapes = []
        state.rows[0] = row
        state.selectRow(row.id)

        let image = makeTestImage(width: 1080, height: 1920)
        state.addImageShape(image: image, centerX: row.templateCenterX(at: 0), centerY: row.templateHeight / 2)

        let added = try #require(state.rows[0].shapes.last)
        #expect(added.deviceCategory == .iphone)
    }

    @Test func clearAllDeviceImagesRemovesScreenshotsFromEveryDevice() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        let rowId = try #require(state.rows.first?.id)
        let images = (0..<state.rows[0].templates.count).map { _ in
            makeTestImage(width: 1206, height: 2622)
        }
        state.batchImportImages(images, into: rowId)

        let devicesBefore = state.rows[0].shapes.filter { $0.type == .device }
        #expect(!devicesBefore.isEmpty)
        #expect(devicesBefore.allSatisfy { $0.screenshotFileName != nil })

        state.clearAllDeviceImages(in: rowId)

        let devicesAfter = state.rows[0].shapes.filter { $0.type == .device }
        #expect(devicesAfter.count == devicesBefore.count, "Device shapes themselves must remain")
        #expect(devicesAfter.allSatisfy { $0.screenshotFileName == nil },
                "All device screenshots should be cleared")
    }

    @Test func clearAllDeviceImagesLeavesNonDeviceImageShapesAlone() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        let rowId = try #require(state.rows.first?.id)
        state.selectRow(rowId)

        // Add a non-device image shape and give it an image file reference.
        let imageShape = CanvasShapeModel(
            id: UUID(), type: .image, x: 50, y: 50, width: 100, height: 100,
            imageFileName: "keep-me.png"
        )
        state.addShape(imageShape)

        // Also fill the default device shapes with screenshots.
        let images = (0..<state.rows[0].templates.count).map { _ in
            makeTestImage(width: 1206, height: 2622)
        }
        state.batchImportImages(images, into: rowId)

        state.clearAllDeviceImages(in: rowId)

        let row = state.rows[0]
        let preservedImage = try #require(row.shapes.first { $0.id == imageShape.id })
        #expect(preservedImage.imageFileName == "keep-me.png",
                "Non-device image shapes must not be touched")
        #expect(row.shapes.filter { $0.type == .device }.allSatisfy { $0.screenshotFileName == nil })
    }

    @Test func clearAllDeviceImagesIsANoOpWhenNothingToClear() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        let rowId = try #require(state.rows.first?.id)
        let shapeIdsBefore = state.rows[0].shapes.map(\.id)

        state.clearAllDeviceImages(in: rowId)

        #expect(state.rows[0].shapes.map(\.id) == shapeIdsBefore,
                "Clearing with no images to clear must not add or remove shapes")
        #expect(state.rows[0].shapes.filter { $0.type == .device }.allSatisfy { $0.screenshotFileName == nil })
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

    @Test func saveAllDoesNotDeleteUnreferencedFontsWhenIndexSaveFails() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        let projectId = try #require(state.activeProjectId)
        let resourcesDir = PersistenceService.resourcesDir(projectId)
        let projectDir = PersistenceService.projectDirectoryURL(projectId)
        let fontURL = resourcesDir.appendingPathComponent("Unused.ttf")
        try Data("font".utf8).write(to: fontURL)

        state.customFonts["Unused.ttf"] = CustomFont(
            fileName: "Unused.ttf",
            familyName: "Unused Family",
            styleName: nil,
            postScriptName: nil,
            isBold: false,
            isItalic: false
        )
        state.everReferencedFontFamilies = ["Unused Family"]

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

        let sourceFontURL = bundledFontURL("Raleway-VariableFont_wght.ttf")
        #expect(FileManager.default.fileExists(atPath: sourceFontURL.path))
        let importedSelection = state.importCustomFont(from: sourceFontURL)
        #expect(importedSelection != nil)

        let projectId = try #require(state.activeProjectId)
        let importedURL = PersistenceService.resourcesDir(projectId).appendingPathComponent(sourceFontURL.lastPathComponent)
        #expect(FileManager.default.fileExists(atPath: importedURL.path))

        state.saveAll()

        let reopened = AppState()
        #expect(FileManager.default.fileExists(atPath: importedURL.path))
        #expect(reopened.customFonts.keys.contains(sourceFontURL.lastPathComponent))
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

    // MARK: - Lock

    @Test func toggleLockOnSelectionLocksAndUnlocks() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        state.selectRow(state.rows.first!.id)
        let shape = CanvasShapeModel(type: .rectangle, x: 100, y: 100, width: 50, height: 50)
        state.addShape(shape)
        state.selectedShapeIds = [shape.id]

        #expect(state.isSelectionFullyLocked == false)
        state.toggleLockOnSelection()
        #expect(state.isSelectionFullyLocked == true)
        #expect(state.rows.first!.shapes.first(where: { $0.id == shape.id })?.resolvedIsLocked == true)

        state.toggleLockOnSelection()
        #expect(state.isSelectionFullyLocked == false)
        #expect(state.rows.first!.shapes.first(where: { $0.id == shape.id })?.resolvedIsLocked == false)
    }

    @Test func toggleLockOnMultiSelectionLocksWhenAnyUnlocked() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        state.selectRow(state.rows.first!.id)
        var a = CanvasShapeModel(type: .rectangle, x: 0, y: 0, width: 50, height: 50)
        a.isLocked = true
        let b = CanvasShapeModel(type: .rectangle, x: 80, y: 0, width: 50, height: 50)
        state.addShape(a)
        state.addShape(b)
        state.selectedShapeIds = [a.id, b.id]

        #expect(state.isSelectionFullyLocked == false)
        #expect(state.isSelectionPartiallyLocked == true)

        state.toggleLockOnSelection()
        #expect(state.isSelectionFullyLocked == true)
    }

    @Test func nudgeSkipsLockedShape() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        state.selectRow(state.rows.first!.id)
        var locked = CanvasShapeModel(type: .rectangle, x: 100, y: 100, width: 50, height: 50)
        locked.isLocked = true
        state.addShape(locked)
        state.selectedShapeIds = [locked.id]

        state.nudgeSelectedShapes(dx: 25, dy: 25)
        let after = state.rows.first!.shapes.first { $0.id == locked.id }!
        #expect(after.x == 100)
        #expect(after.y == 100)
    }

    @Test func applyGroupDragSkipsLockedShape() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        state.selectRow(state.rows.first!.id)
        var locked = CanvasShapeModel(type: .rectangle, x: 0, y: 0, width: 50, height: 50)
        locked.isLocked = true
        let unlocked = CanvasShapeModel(type: .rectangle, x: 200, y: 0, width: 50, height: 50)
        state.addShape(locked)
        state.addShape(unlocked)
        state.selectedShapeIds = [locked.id, unlocked.id]

        state.applyGroupDrag(offset: CGSize(width: 30, height: 30))

        let afterLocked = state.rows.first!.shapes.first { $0.id == locked.id }!
        let afterUnlocked = state.rows.first!.shapes.first { $0.id == unlocked.id }!
        #expect(afterLocked.x == 0)
        #expect(afterLocked.y == 0)
        #expect(afterUnlocked.x == 230)
        #expect(afterUnlocked.y == 30)
    }

    @Test func duplicateShapeForOptionDragSkipsLocked() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        state.selectRow(state.rows.first!.id)
        var locked = CanvasShapeModel(type: .rectangle, x: 0, y: 0, width: 50, height: 50)
        locked.isLocked = true
        state.addShape(locked)
        let countBefore = state.rows.first!.shapes.count

        let newId = state.duplicateShapeForOptionDrag(locked.id)
        #expect(newId == nil)
        #expect(state.rows.first!.shapes.count == countBefore)
    }

    @Test func deleteShapeSkipsLocked() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        state.selectRow(state.rows.first!.id)
        var locked = CanvasShapeModel(type: .rectangle, x: 0, y: 0, width: 50, height: 50)
        locked.isLocked = true
        state.addShape(locked)

        state.deleteShape(locked.id)
        #expect(state.rows.first!.shapes.contains { $0.id == locked.id })
    }

    @Test func deleteSelectedShapesSkipsLocked() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        state.selectRow(state.rows.first!.id)
        var locked = CanvasShapeModel(type: .rectangle, x: 0, y: 0, width: 50, height: 50)
        locked.isLocked = true
        let unlocked = CanvasShapeModel(type: .rectangle, x: 200, y: 0, width: 50, height: 50)
        state.addShape(locked)
        state.addShape(unlocked)
        state.selectedShapeIds = [locked.id, unlocked.id]

        state.deleteSelectedShapes()
        #expect(state.rows.first!.shapes.contains { $0.id == locked.id })
        #expect(!state.rows.first!.shapes.contains { $0.id == unlocked.id })
    }

    @Test func updateShapeAllowsPropertyEditOnLockedShape() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        state.selectRow(state.rows.first!.id)
        var locked = CanvasShapeModel(type: .rectangle, x: 100, y: 100, width: 50, height: 50)
        locked.isLocked = true
        state.addShape(locked)

        var attempt = locked
        attempt.opacity = 0.25
        state.updateShape(attempt)

        let after = state.rows.first!.shapes.first { $0.id == locked.id }!
        #expect(after.opacity == 0.25, "Properties bar should still be able to edit locked shapes")
        #expect(after.resolvedIsLocked, "Lock state is preserved across property edits")
    }

    @Test func updateShapesEditsLockedShapesToo() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        state.selectRow(state.rows.first!.id)
        var locked = CanvasShapeModel(type: .rectangle, x: 0, y: 0, width: 50, height: 50)
        locked.isLocked = true
        let unlocked = CanvasShapeModel(type: .rectangle, x: 200, y: 0, width: 50, height: 50)
        state.addShape(locked)
        state.addShape(unlocked)
        state.selectedShapeIds = [locked.id, unlocked.id]

        state.updateShapes(state.selectedShapeIds) { $0.opacity = 0.5 }

        let afterLocked = state.rows.first!.shapes.first { $0.id == locked.id }!
        let afterUnlocked = state.rows.first!.shapes.first { $0.id == unlocked.id }!
        #expect(afterLocked.opacity == 0.5)
        #expect(afterUnlocked.opacity == 0.5)
        #expect(afterLocked.resolvedIsLocked, "Lock state survives multi-select property edit")
    }

    @Test func nudgeOnFullyLockedSelectionDoesNotPoisonUndoBaseline() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let firstRowId = state.rows.first!.id
        state.selectRow(firstRowId)
        var locked = CanvasShapeModel(type: .rectangle, x: 100, y: 100, width: 50, height: 50)
        locked.isLocked = true
        state.addShape(locked)
        state.selectedShapeIds = [locked.id]
        state.nudgeSelectedShapes(dx: 25, dy: 25)

        state.addRow()
        let newRowId = state.rows.last!.id
        state.selectRow(newRowId)
        let movable = CanvasShapeModel(type: .rectangle, x: 100, y: 100, width: 50, height: 50)
        state.addShape(movable)
        state.selectedShapeIds = [movable.id]
        state.nudgeSelectedShapes(dx: 5, dy: 0)

        let movedShape = state.rows.last!.shapes.first { $0.id == movable.id }!
        #expect(movedShape.x == 105, "Nudge should move the unlocked shape in the new row")
    }

    @Test func saveImageSkipsLockedShape() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        state.selectRow(state.rows.first!.id)
        var locked = CanvasShapeModel(type: .device, x: 0, y: 0, width: 100, height: 200, deviceCategory: .iphone)
        locked.isLocked = true
        state.addShape(locked)

        state.saveImage(makeTestImage(width: 100, height: 200), for: locked.id)

        let after = state.rows.first!.shapes.first { $0.id == locked.id }!
        #expect(after.screenshotFileName == nil, "Drag-and-drop image must not overwrite locked device")
    }

    @Test func clearImageSkipsLockedShape() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        state.selectRow(state.rows.first!.id)
        var locked = CanvasShapeModel(type: .image, x: 0, y: 0, width: 100, height: 100)
        locked.imageFileName = "test.png"
        locked.isLocked = true
        state.addShape(locked)

        state.clearImage(for: locked.id)

        let after = state.rows.first!.shapes.first { $0.id == locked.id }!
        #expect(after.imageFileName == "test.png")
    }

    @Test func centerAllDevicesSkipsLocked() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let rowId = state.rows.first!.id
        state.selectRow(rowId)
        var locked = CanvasShapeModel(type: .device, x: 10, y: 10, width: 50, height: 100, deviceCategory: .iphone)
        locked.isLocked = true
        state.addShape(locked)

        state.centerAllDevices(in: rowId, axis: .both)

        let after = state.rows.first!.shapes.first { $0.id == locked.id }!
        #expect(after.x == 10)
        #expect(after.y == 10)
    }

    @Test func alignSelectedShapesSkipsLocked() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        state.selectRow(state.rows.first!.id)
        var locked = CanvasShapeModel(type: .rectangle, x: 0, y: 100, width: 50, height: 50)
        locked.isLocked = true
        let a = CanvasShapeModel(type: .rectangle, x: 200, y: 200, width: 50, height: 50)
        let b = CanvasShapeModel(type: .rectangle, x: 400, y: 300, width: 50, height: 50)
        state.addShape(locked)
        state.addShape(a)
        state.addShape(b)
        state.selectedShapeIds = [locked.id, a.id, b.id]

        state.alignSelectedShapes(.top)

        let afterLocked = state.rows.first!.shapes.first { $0.id == locked.id }!
        let afterA = state.rows.first!.shapes.first { $0.id == a.id }!
        let afterB = state.rows.first!.shapes.first { $0.id == b.id }!
        #expect(afterLocked.y == 100, "Locked shape should not move during align")
        #expect(afterA.y == afterB.y, "Unlocked shapes align to the topmost unlocked")
        #expect(afterA.y == 200)
    }
}
