import AppKit
import CoreGraphics
@testable import Screenshot_Bro
import SwiftUI
import Testing

extension AppStateTests {
    @Test func localizedFolderImportIsOneUndoStepAcrossLocales() async throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let rowId = try #require(state.rows.first?.id)
        let before = state.rows
        let beforeLocales = state.localeState
        let um = try #require(state.undoManager)
        um.removeAllActions()

        let count = state.rows[0].templates.count
        let images = (0..<count).map { _ in makeTestImage(width: 1206, height: 2622) }
        let imported = await state.importLocalizedScreenshots(
            [(localeCode: "en", sources: importSources(images)), (localeCode: "de", sources: importSources(images))],
            into: rowId,
            addingLocales: [LocaleDefinition(code: "de", label: "German")]
        )

        #expect(imported == count * 2)
        #expect(state.localeState.hasLocale("de"))
        let devices = state.rows[0].shapes.filter { $0.type == .device }
        #expect(devices.allSatisfy { $0.screenshotFileName != nil })
        #expect(devices.allSatisfy { state.localeState.overrides["de"]?[$0.id.uuidString]?.overrideImageFileName != nil })

        um.undo()
        #expect(state.rows == before)
        #expect(state.localeState == beforeLocales)
        #expect(!um.canUndo)
    }

    @Test func localizedFolderImportCountsOnlyScreenshotsAlreadySetPerLanguage() async throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let rowId = try #require(state.rows.first?.id)
        let count = state.rows[0].templates.count
        let files = (0..<count).map { URL(fileURLWithPath: "/tmp/\($0).png") }
        let plan = LocaleFolderImportPlan(batches: [
            .init(localeCode: "en", files: files),
            .init(localeCode: "de", files: files),
        ])
        #expect(state.screenshotsReplaced(by: plan, inRow: rowId) == 0)

        let images = (0..<count).map { _ in makeTestImage(width: 1206, height: 2622) }
        await state.importLocalizedScreenshots(
            [(localeCode: "en", sources: importSources(images))],
            into: rowId,
            addingLocales: [LocaleDefinition(code: "de", label: "German")]
        )

        // German still falls back to the base images, so importing it replaces nothing.
        #expect(state.screenshotsReplaced(by: plan, inRow: rowId) == count)
    }

    /// A 200×200 picture zoomed 2× in a 200×200 frame, so it can pan half a frame each way.
    func addCroppableImage(to state: AppState) -> CanvasShapeModel {
        var shape = CanvasShapeModel(type: .image, x: 100, y: 100, width: 200, height: 200)
        shape.imageFileName = "crop.png"
        shape.imageCrop = ImageCrop(scale: 2)
        state.rows[0].shapes.append(shape)
        state.screenshotImages["crop.png"] = makeTestImage(width: 200, height: 200)
        return shape
    }

    @Test func arrowKeysPanThePictureInCropMode() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let shape = addCroppableImage(to: state)
        state.beginImageCrop(shape.id)
        #expect(state.imageCrop.shapeId == shape.id)
        let um = try #require(state.undoManager)
        um.removeAllActions()

        state.nudgeSelectedShapes(dx: 10, dy: 0)
        state.nudgeSelectedShapes(dx: 0, dy: -10)
        state.finishNudgeIfNeeded()

        let cropped = try #require(state.rows[0].shapes.first { $0.id == shape.id })
        #expect(cropped.x == shape.x && cropped.y == shape.y)
        #expect(cropped.imageCrop == ImageCrop(scale: 2, offsetX: 0.05, offsetY: -0.05))

        um.undo()
        #expect(state.rows[0].shapes.first { $0.id == shape.id }?.imageCrop == shape.imageCrop)
        #expect(!um.canUndo)
    }

    @Test func enteringCropModeSplitsAMoveFromACropPanInUndo() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let shape = addCroppableImage(to: state)
        state.selectShape(shape.id, in: state.rows[0].id)
        try #require(state.undoManager).removeAllActions()

        state.nudgeSelectedShapes(dx: 10, dy: 0)
        state.beginImageCrop(shape.id)
        state.nudgeSelectedShapes(dx: 10, dy: 0)
        state.endImageCrop()

        // The app's ⌘Z path, which commits a still-pending pan before undoing.
        state.undoDocumentAction()
        let afterFirstUndo = try #require(state.rows[0].shapes.first { $0.id == shape.id })
        #expect(afterFirstUndo.x == shape.x + 10)
        #expect(afterFirstUndo.imageCrop == shape.imageCrop)
        state.undoDocumentAction()
        #expect(state.rows[0].shapes.first { $0.id == shape.id }?.x == shape.x)
    }

    @Test func lockingEndsCropModeAndLockedCropsCantBeReset() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let shape = addCroppableImage(to: state)
        state.beginImageCrop(shape.id)

        state.toggleLockOnSelection()
        #expect(!state.imageCrop.isActive)

        state.resetImageCrop(shape.id)
        #expect(state.rows[0].shapes.first { $0.id == shape.id }?.imageCrop == shape.imageCrop)
    }

    @Test func resetCropGrowsTheFrameBackAroundTheWholePicture() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        // 2× zoom panned right by a quarter frame: the 400×400 picture is centred 50 right of the frame.
        var shape = addCroppableImage(to: state)
        shape.imageCrop = ImageCrop(scale: 2, offsetX: 0.25)
        state.rows[0].shapes[state.rows[0].shapes.count - 1] = shape
        #expect(state.canResetImageCrop(shape))

        state.resetImageCrop(shape.id)

        let reset = try #require(state.rows[0].shapes.first { $0.id == shape.id })
        #expect(reset.imageCrop == nil)
        #expect(reset.x == 50 && reset.y == 0)
        #expect(reset.width == 400 && reset.height == 400)
        #expect(!state.canResetImageCrop(reset))
    }

    @Test func resetCropWithoutADecodedPictureStillClearsTheCrop() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let shape = addCroppableImage(to: state)
        state.screenshotImages["crop.png"] = nil

        state.resetImageCrop(shape.id)

        let reset = try #require(state.rows[0].shapes.first { $0.id == shape.id })
        #expect(reset.imageCrop == nil)
        #expect(reset.frameRect == shape.frameRect)
    }

    @Test func anUncroppedPictureThatOverflowsItsFrameHasNothingToReset() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        var shape = addCroppableImage(to: state)
        shape.imageCrop = nil
        shape.height = 100
        state.rows[0].shapes[state.rows[0].shapes.count - 1] = shape
        #expect(!state.canResetImageCrop(shape))
    }

    @Test func cropInANonBaseLocaleStaysInThatLocale() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let shape = addCroppableImage(to: state)
        state.addLocale(.init(code: "de", label: "German"))
        state.setActiveLocale("de")
        state.beginImageCrop(shape.id)
        let um = try #require(state.undoManager)
        um.removeAllActions()

        state.nudgeSelectedShapes(dx: 10, dy: 0)
        state.finishNudgeIfNeeded()

        let base = try #require(state.rows[0].shapes.first { $0.id == shape.id })
        #expect(base.imageCrop == shape.imageCrop)
        #expect(LocaleService.resolveShape(base, localeState: state.localeState).imageCrop == ImageCrop(scale: 2, offsetX: 0.05))

        // Reset clears the German crop to the uncropped picture without touching the base's.
        state.resetImageCrop(shape.id)
        let afterReset = try #require(state.rows[0].shapes.first { $0.id == shape.id })
        #expect(afterReset.imageCrop == shape.imageCrop)
        #expect(afterReset.width == shape.width)
        let resolvedReset = LocaleService.resolveShape(afterReset, localeState: state.localeState)
        #expect(resolvedReset.imageCrop == nil)
        #expect(resolvedReset.width == 400)

        um.undo()
        um.undo()
        let restored = try #require(state.rows[0].shapes.first { $0.id == shape.id })
        #expect(LocaleService.resolveShape(restored, localeState: state.localeState).imageCrop == shape.imageCrop)
        #expect(state.localeState.overrides["de"]?[shape.id.uuidString] == nil)
    }

    @Test func batchImportImagesReusesExistingDeviceShapes() async throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        let rowId = try #require(state.rows.first?.id)
        let originalDevices = state.rows[0].shapes.filter { $0.type == .device }
        #expect(originalDevices.count == state.rows[0].templates.count)

        let images = (0..<state.rows[0].templates.count).map { _ in
            makeTestImage(width: 1206, height: 2622)
        }

        await state.batchImportImages(importSources(images), into: rowId, source: .dropRow)

        let row = state.rows[0]
        let devices = row.shapes.filter { $0.type == .device }
        #expect(devices.count == originalDevices.count)
        #expect(Set(devices.map(\.id)) == Set(originalDevices.map(\.id)))
        #expect(devices.allSatisfy { $0.screenshotFileName != nil })
        #expect(row.shapes.filter { $0.type == .image }.isEmpty)
    }

    @Test func batchImportImagesCreatesMissingDeviceUsingMostCommonRowFrame() async throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        let commonFrameId = "iphone17-black-portrait"
        let commonFrame = try #require(DeviceFrameCatalog.frame(for: commonFrameId))
        let alternateFrame = try #require(DeviceFrameCatalog.frame(for: "iphone17-lavender-portrait"))

        var row = state.rows[0]
        row.templates = Array(row.templates.prefix(2))
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

        await state.batchImportImages(importSources(images), into: row.id, source: .dropRow)

        let updatedRow = state.rows[0]
        let devices = updatedRow.shapes.filter { $0.type == .device }
        #expect(devices.count == 3)

        let createdDevice = try #require(devices.first {
            updatedRow.owningTemplateIndex(for: $0) == 2
        })
        let createdFrameId = try #require(createdDevice.deviceFrameId)
        let createdFrame = try #require(DeviceFrameCatalog.frame(for: createdFrameId))
        #expect(createdFrame.modelName == commonFrame.modelName)
        #expect(createdFrame.isLandscape == commonFrame.isLandscape)
        #expect(createdDevice.screenshotFileName != nil)
    }

    @Test func landscapeScreenshotGetsLandscapeFrameWhenRowHasNoMatchingFrame() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        let iphoneFrameId = try #require(DeviceFrameCatalog.firstPortraitFrameId(for: .iphone))
        var row = state.rows[0]
        row.defaultDeviceFrameId = iphoneFrameId
        row.shapes = []

        let shape = state.makeImageShape(
            image: makeTestImage(width: 2420, height: 1668),
            row: row,
            centerX: row.templateWidth / 2,
            centerY: row.templateHeight / 2
        )

        #expect(shape.type == .device)
        #expect(shape.deviceFrameId == "ipadpro11-silver-landscape")
        #expect(shape.deviceCategory == .ipadPro11)
        #expect(shape.width > shape.height)
        #expect(shape.width <= row.templateWidth * 0.9)
    }

    @Test func portraitScreenshotStillUsesGenericFrameWhenRowHasNoMatchingFrame() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        let iphoneFrameId = try #require(DeviceFrameCatalog.firstPortraitFrameId(for: .iphone))
        var row = state.rows[0]
        row.defaultDeviceFrameId = iphoneFrameId
        row.shapes = []

        let shape = state.makeImageShape(
            image: makeTestImage(width: 1668, height: 2420),
            row: row,
            centerX: row.templateWidth / 2,
            centerY: row.templateHeight / 2
        )

        #expect(shape.type == .device)
        #expect(shape.deviceFrameId == nil)
        #expect(shape.deviceCategory == .ipadPro11)
        #expect(shape.height > shape.width)
    }

    @Test func landscapeScreenshotFlipsExistingRowFrameToLandscape() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        let ipadFrameId = try #require(DeviceFrameCatalog.firstPortraitFrameId(for: .ipadPro13))
        var row = state.rows[0]
        row.defaultDeviceFrameId = ipadFrameId
        row.shapes = []

        let shape = state.makeImageShape(
            image: makeTestImage(width: 2752, height: 2064),
            row: row,
            centerX: row.templateWidth / 2,
            centerY: row.templateHeight / 2
        )

        #expect(shape.deviceFrameId == "ipadpro13-silver-landscape")
        #expect(shape.width > shape.height)
        #expect(shape.width <= row.templateWidth * 0.9)
    }

    @Test func batchImportImagesSkipsTemplatesWithoutDevices() async throws {
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

        await state.batchImportImages(importSources(images), into: row.id, source: .dropRow)

        let updatedRow = state.rows[0]
        #expect(updatedRow.templates.count == 3, "No new templates should be appended")

        let devices = updatedRow.shapes.filter { $0.type == .device }
        #expect(devices.count == 2, "No new devices should be added to template 1")
        #expect(devices.allSatisfy { $0.screenshotFileName != nil })

        let deviceTemplateIndices = Set(devices.compactMap { updatedRow.owningTemplateIndex(for: $0) })
        #expect(deviceTemplateIndices == [0, 2])
    }

    /// The PNG passthrough writes the source bytes verbatim instead of decoding and re-deflating.
    /// Transparency has to survive that — Remove Background depends on alpha round-tripping.
    @Test func batchImportPassthroughPreservesSourcePNGBytesAndAlpha() async throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        let rowId = try #require(state.rows.first?.id)
        let activeId = try #require(state.activeProjectId)

        let transparent = makeTransparentTestImage(width: 1206, height: 2622)
        let sourceData = try #require(ExportService.pngData(from: transparent))
        let sourceURL = tempDir.appendingPathComponent("source-\(UUID().uuidString).png")
        try sourceData.write(to: sourceURL)

        _ = await state.batchImportImages(
            [ImageImportSource(image: transparent, sourceURL: sourceURL)],
            into: rowId,
            source: .dropRow
        )

        let device = try #require(state.rows[0].shapes.first { $0.type == .device })
        let fileName = try #require(device.displayImageFileName)
        let written = try Data(contentsOf: PersistenceService.resourcesDir(activeId)
            .appendingPathComponent(fileName))

        #expect(written == sourceData, "passthrough should copy the source bytes verbatim")
        let rep = try #require(NSBitmapImageRep(data: written))
        #expect(rep.hasAlpha)
    }

    /// Non-PNG sources (and drag-and-drop, which has no URL at all) fall back to the off-main
    /// encode and must still land a valid, correctly sized resource.
    @Test func batchImportWithoutSourceURLStillWritesResource() async throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        let rowId = try #require(state.rows.first?.id)
        let activeId = try #require(state.activeProjectId)

        _ = await state.batchImportImages(
            [ImageImportSource(image: makeTestImage(width: 1206, height: 2622))],
            into: rowId,
            source: .dropRow
        )

        let device = try #require(state.rows[0].shapes.first { $0.type == .device })
        let fileName = try #require(device.displayImageFileName)
        let written = try Data(contentsOf: PersistenceService.resourcesDir(activeId)
            .appendingPathComponent(fileName))
        let rep = try #require(NSBitmapImageRep(data: written))
        #expect(rep.pixelsWide == 1206)
        #expect(rep.pixelsHigh == 2622)
        #expect(state.screenshotImages[fileName] != nil, "editor thumbnail should be published")
    }

    /// The regression this whole path exists to prevent: a 20-image import used to run as one
    /// uninterrupted main-actor job (1.5-3.1 s) and trip Sentry's 3 s app-hang watchdog
    /// (SCREENSHOT-BRO-W). Counting how often a competing main-actor task gets a slot during the
    /// import is what separates "moved off the main actor" from "still inline" — a `nonisolated`
    /// helper without `@concurrent` would inherit this actor and starve the ticker completely.
    @Test func batchImportLetsTheMainActorRunBetweenImages() async throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        let rowId = try #require(state.rows.first?.id)
        let images = importSources((0..<20).map { _ in makeTestImage(width: 1206, height: 2622) })

        let ticker = MainActorTicker()
        let tickTask = Task { @MainActor in
            while !Task.isCancelled {
                ticker.ticks += 1
                await Task.yield()
            }
        }

        // Sampled immediately before the call: no suspension point separates them, so the delta is
        // exactly the number of main-actor turns the import itself left available.
        let ticksBefore = ticker.ticks
        let imported = await state.batchImportImages(images, into: rowId, source: .dropRow)
        let ticksDuring = ticker.ticks - ticksBefore
        tickTask.cancel()

        #expect(imported == 20)
        #expect(ticksDuring >= 20,
                "main actor ran only \(ticksDuring) times across a 20-image import — the encode/write is still inline")
    }

    /// The encode/write flush runs after the undo step commits, so the row it imported into can be
    /// deleted out from under it. That must not crash, and the resources it already wrote must not
    /// keep the deleted row alive in the document.
    @Test func batchImportSurvivesRowDeletionDuringTheWriteFlush() async throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        // `deleteRow` is a no-op on the last remaining row.
        state.addRow()
        let rowId = try #require(state.rows.first?.id)
        #expect(state.rows.count > 1)

        let images = (0..<3).map { _ in
            ImageImportSource(image: makeTestImage(width: 1206, height: 2622))
        }

        async let imported = state.batchImportImages(images, into: rowId, source: .dropRow)
        await Task.yield()
        state.deleteRow(rowId)

        #expect(await imported == 3)
        #expect(!state.rows.contains { $0.id == rowId })
    }

    @Test func batchImportImagesAppendsTemplatesForOverflowImages() async throws {
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

        await state.batchImportImages(importSources(images), into: row.id, source: .dropRow)

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
        state.addImageShape(image: image, centerX: row.templateCenterX(at: 0), centerY: row.templateHeight / 2, source: .dropCanvas)

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
        state.addImageShape(image: image, centerX: row.templateCenterX(at: 0), centerY: row.templateHeight / 2, source: .dropCanvas)

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
        state.addImageShape(image: image, centerX: row.templateCenterX(at: 0), centerY: row.templateHeight / 2, source: .dropCanvas)

        let added = try #require(state.rows[0].shapes.last)
        #expect(added.deviceCategory == .iphone)
    }

    @Test func clearAllDeviceImagesRemovesScreenshotsFromEveryDevice() async throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        let rowId = try #require(state.rows.first?.id)
        let images = (0..<state.rows[0].templates.count).map { _ in
            makeTestImage(width: 1206, height: 2622)
        }
        await state.batchImportImages(importSources(images), into: rowId, source: .dropRow)

        let devicesBefore = state.rows[0].shapes.filter { $0.type == .device }
        #expect(!devicesBefore.isEmpty)
        #expect(devicesBefore.allSatisfy { $0.screenshotFileName != nil })

        state.clearAllDeviceImages(in: rowId)

        let devicesAfter = state.rows[0].shapes.filter { $0.type == .device }
        #expect(devicesAfter.count == devicesBefore.count, "Device shapes themselves must remain")
        #expect(devicesAfter.allSatisfy { $0.screenshotFileName == nil },
                "All device screenshots should be cleared")
    }

    @Test func clearAllDeviceImagesLeavesNonDeviceImageShapesAlone() async throws {
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
        await state.batchImportImages(importSources(images), into: rowId, source: .dropRow)

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
}
