import AppKit
import CoreGraphics
@testable import Screenshot_Bro
import SwiftUI
import Testing

extension AppStateTests {
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

        state.saveImage(makeTestImage(width: 100, height: 200), for: locked.id, source: .picker)

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

    @Test func clearImageOnBaseLocaleClearsImage() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        state.selectRow(state.rows.first!.id)
        var shape = CanvasShapeModel(type: .image, x: 0, y: 0, width: 100, height: 100)
        shape.imageFileName = "base.png"
        state.addShape(shape)

        state.clearImage(for: shape.id)

        let after = state.rows.first!.shapes.first { $0.id == shape.id }!
        #expect(after.imageFileName == nil)
    }

    @Test func clearImageOnNonBaseLocaleWithoutOverrideClearsBaseImage() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        state.selectRow(state.rows.first!.id)
        var shape = CanvasShapeModel(type: .image, x: 0, y: 0, width: 100, height: 100)
        shape.imageFileName = "base.png"
        state.addShape(shape)
        state.addLocale(.init(code: "uk", label: "Ukrainian"))
        state.setActiveLocale("uk")

        state.clearImage(for: shape.id)

        let after = state.rows.first!.shapes.first { $0.id == shape.id }!
        #expect(after.imageFileName == nil, "With no per-locale override, Reset must clear the inherited base image")
    }

    @Test func clearImageOnNonBaseLocaleWithOverrideRemovesOnlyOverride() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        state.selectRow(state.rows.first!.id)
        var shape = CanvasShapeModel(type: .image, x: 0, y: 0, width: 100, height: 100)
        shape.imageFileName = "base.png"
        state.addShape(shape)
        state.addLocale(.init(code: "uk", label: "Ukrainian"))
        state.setActiveLocale("uk")
        var override = ShapeLocaleOverride()
        override.overrideImageFileName = "uk.png"
        LocaleService.setShapeOverride(&state.localeState, shapeId: shape.id, override: override)

        state.clearImage(for: shape.id)

        #expect(state.localeState.override(forCode: "uk", shapeId: shape.id)?.overrideImageFileName == nil)
        let after = state.rows.first!.shapes.first { $0.id == shape.id }!
        #expect(after.imageFileName == "base.png", "Removing the locale override must leave the base image alone")
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

    @Test func centerShapesCentersNonDevice() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let rowId = state.rows.first!.id
        state.selectRow(rowId)
        let row = state.rows.first!
        let shape = CanvasShapeModel(type: .rectangle, x: 7, y: 13, width: 80, height: 120)
        state.addShape(shape)

        state.centerShapes([shape.id], in: rowId, axis: .both)

        let after = state.rows.first!.shapes.first { $0.id == shape.id }!
        #expect(after.x == (row.templateWidth - 80) / 2)
        #expect(after.y == (row.templateHeight - 120) / 2)
    }

    @Test func centerShapesSkipsLocked() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let rowId = state.rows.first!.id
        state.selectRow(rowId)
        var locked = CanvasShapeModel(type: .rectangle, x: 10, y: 10, width: 50, height: 100)
        locked.isLocked = true
        state.addShape(locked)

        state.centerShapes([locked.id], in: rowId, axis: .both)

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

    // MARK: - Shadow (multi-selection)

    @Test func updateShapesAppliesShadowToAllSelectedDevices() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        state.selectRow(state.rows.first!.id)

        let d1 = CanvasShapeModel(id: UUID(), type: .device, x: 0, y: 0, deviceCategory: .iphone)
        let d2 = CanvasShapeModel(id: UUID(), type: .device, x: 100, y: 0, deviceCategory: .iphone)
        state.addShape(d1)
        state.addShape(d2)
        state.selectedShapeIds = [d1.id, d2.id]

        state.updateShapes(state.selectedShapeIds) { $0.shadow = .strong }

        let shapes = state.rows.first!.shapes
        let s1 = shapes.first { $0.id == d1.id }!
        let s2 = shapes.first { $0.id == d2.id }!
        #expect(s1.shadow?.isActive == true)
        #expect(s2.shadow?.isActive == true)
        #expect(s1.shadow?.matchingPreset == .strong)
        #expect(s2.shadow?.matchingPreset == .strong)

        // Clearing an empty config drops it back to nil on all selected devices.
        state.updateShapes(state.selectedShapeIds) { shape in
            let empty = ShadowConfig()
            shape.shadow = empty.isEmpty ? nil : empty
        }
        let cleared = state.rows.first!.shapes
        #expect(cleared.first { $0.id == d1.id }!.shadow == nil)
        #expect(cleared.first { $0.id == d2.id }!.shadow == nil)
    }
}
