import AppKit
import CoreGraphics
@testable import Screenshot_Bro
import SwiftUI
import Testing

extension AppStateTests {
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

    @Test func removeTemplateKeepsShapeSpanningIntoNeighbor() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let rowId = state.rows.first!.id
        state.selectRow(rowId)
        state.addTemplate(to: rowId)
        state.addTemplate(to: rowId)
        let tw = state.rows.first!.templateWidth
        let spanning = CanvasShapeModel(
            type: .rectangle,
            x: 0.5 * tw,
            y: 0,
            width: 2 * tw,
            height: 100
        )
        state.addShape(spanning)
        let removedTemplateId = state.rows.first!.templates[1].id
        state.removeTemplate(removedTemplateId, from: rowId)
        let row = state.rows.first!
        #expect(row.shapes.contains { $0.id == spanning.id }, "Spanning shape should survive deletion of a template it overlaps")
        #expect(row.visibleShapes(forTemplateAt: 0).contains { $0.id == spanning.id }, "Shape should still be visible on template 0")
    }

    @Test func removeTemplateDeletesShapeContainedInIt() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let rowId = state.rows.first!.id
        state.selectRow(rowId)
        state.addTemplate(to: rowId)
        state.addTemplate(to: rowId)
        let tw = state.rows.first!.templateWidth
        let contained = CanvasShapeModel(
            type: .rectangle,
            x: 1.1 * tw,
            y: 0,
            width: 0.5 * tw,
            height: 100
        )
        state.addShape(contained)
        let removedTemplateId = state.rows.first!.templates[1].id
        state.removeTemplate(removedTemplateId, from: rowId)
        #expect(!state.rows.first!.shapes.contains { $0.id == contained.id }, "Shape fully inside the deleted template should be removed")
    }

    @Test func removeTemplateDeletesClippedShapeRegardlessOfWidth() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let rowId = state.rows.first!.id
        state.selectRow(rowId)
        state.addTemplate(to: rowId)
        state.addTemplate(to: rowId)
        let tw = state.rows.first!.templateWidth
        // Wide enough to span 3 templates, but clipToTemplate confines it to its owner.
        let clipped = CanvasShapeModel(
            type: .rectangle,
            x: 0.5 * tw,
            y: 0,
            width: 2 * tw,
            height: 100,
            clipToTemplate: true
        )
        state.addShape(clipped)
        let removedTemplateId = state.rows.first!.templates[1].id
        state.removeTemplate(removedTemplateId, from: rowId)
        #expect(!state.rows.first!.shapes.contains { $0.id == clipped.id }, "Clipped shape owned by the deleted template should be removed")
    }

    /// Sits inside template 1, but the 15° rotation makes its AABB cross the column edge.
    func tiltedShapeInTemplate1(templateWidth tw: CGFloat) -> CanvasShapeModel {
        CanvasShapeModel(
            type: .rectangle,
            x: tw + (tw - 1000) / 2,
            y: 0,
            width: 1000,
            height: 2000,
            rotation: 15
        )
    }

    @Test func removeTemplateDeletesTiltedShapeBleedingPastColumnEdge() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let rowId = state.rows.first!.id
        state.selectRow(rowId)
        let tilted = tiltedShapeInTemplate1(templateWidth: state.rows.first!.templateWidth)
        state.addShape(tilted)
        let removedTemplateId = state.rows.first!.templates[1].id
        state.removeTemplate(removedTemplateId, from: rowId)
        #expect(!state.rows.first!.shapes.contains { $0.id == tilted.id }, "Tilted shape belonging to the deleted template should be removed, not orphaned")
    }

    @Test func moveTemplateRightMovesContainedShapeWithItsColumn() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let rowId = state.rows.first!.id
        state.selectRow(rowId)
        let tw = state.rows.first!.templateWidth
        let shape = CanvasShapeModel(type: .rectangle, x: 0.25 * tw, y: 0, width: 0.5 * tw, height: 100)
        state.addShape(shape)
        let movedTemplateId = state.rows.first!.templates[0].id
        state.moveTemplateRight(movedTemplateId, in: rowId)
        let row = state.rows.first!
        #expect(row.templates[1].id == movedTemplateId)
        let moved = try #require(row.shapes.first { $0.id == shape.id })
        #expect(moved.x == shape.x + tw, "Shape should follow its template to the new column")
    }

    @Test func moveTemplateMovesShapeBleedingSlightlyPastColumnEdge() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let rowId = state.rows.first!.id
        state.selectRow(rowId)
        let tw = state.rows.first!.templateWidth
        // Full-bleed image shape drifted 2px into the previous column (typical after display-scale drags).
        let fullBleed = CanvasShapeModel(type: .image, x: tw - 2, y: 0, width: tw, height: 100)
        state.addShape(fullBleed)
        let movedTemplateId = state.rows.first!.templates[1].id
        state.moveTemplateRight(movedTemplateId, in: rowId)
        let moved = try #require(state.rows.first!.shapes.first { $0.id == fullBleed.id })
        #expect(moved.x == fullBleed.x + tw, "Slight overhang must not detach the shape from its column")
    }

    @Test func moveTemplateMovesTiltedShapeWhoseBoundsCrossColumnEdge() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let rowId = state.rows.first!.id
        state.selectRow(rowId)
        let tw = state.rows.first!.templateWidth
        let tilted = tiltedShapeInTemplate1(templateWidth: tw)
        state.addShape(tilted)
        let movedTemplateId = state.rows.first!.templates[1].id
        state.moveTemplateLeft(movedTemplateId, in: rowId)
        let moved = try #require(state.rows.first!.shapes.first { $0.id == tilted.id })
        #expect(moved.x == tilted.x - tw, "Rotation widening the AABB past the edge must not detach the shape from its column")
    }

    @Test func moveTemplateKeepsDeliberateStraddlerInPlace() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let rowId = state.rows.first!.id
        state.selectRow(rowId)
        let tw = state.rows.first!.templateWidth
        // Half in template 0, half in template 1 — a deliberate cross-panel shape.
        let straddler = CanvasShapeModel(type: .rectangle, x: 0.5 * tw, y: 0, width: tw, height: 100)
        state.addShape(straddler)
        let movedTemplateId = state.rows.first!.templates[0].id
        state.moveTemplateRight(movedTemplateId, in: rowId)
        let after = try #require(state.rows.first!.shapes.first { $0.id == straddler.id })
        #expect(after.x == straddler.x, "Shapes meaningfully spanning columns should stay in place")
    }

    @Test func moveTemplateMovesLastColumnImageBleedingOffRowEnd() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let rowId = state.rows.first!.id
        state.selectRow(rowId)
        let tw = state.rows.first!.templateWidth
        // 0.6 tw of it hangs off the row's right end, over no template.
        let image = CanvasShapeModel(type: .image, x: 2 * tw, y: 0, width: 1.6 * tw, height: 100)
        state.addShape(image)
        let movedTemplateId = state.rows.first!.templates[2].id
        state.moveTemplateLeft(movedTemplateId, in: rowId)
        let moved = try #require(state.rows.first!.shapes.first { $0.id == image.id })
        #expect(moved.x == image.x - tw, "Bleed off the row end must not detach the image from its column")
    }

    @Test func moveTemplateMovesFirstColumnImageBleedingOffRowStart() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let rowId = state.rows.first!.id
        state.selectRow(rowId)
        let tw = state.rows.first!.templateWidth
        let image = CanvasShapeModel(type: .image, x: -0.6 * tw, y: 0, width: 1.6 * tw, height: 100)
        state.addShape(image)
        let movedTemplateId = state.rows.first!.templates[0].id
        state.moveTemplateRight(movedTemplateId, in: rowId)
        let moved = try #require(state.rows.first!.shapes.first { $0.id == image.id })
        #expect(moved.x == image.x + tw, "Bleed off the row start must not detach the image from its column")
    }

    @Test func rapidMoveRightOnDisplacedNeighborKeepsMovingSameTemplate() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let rowId = state.rows.first!.id
        let ids = state.rows.first!.templates.map(\.id)

        state.moveTemplateRight(ids[0], in: rowId)
        #expect(state.rows.first!.templates.map(\.id) == [ids[1], ids[0], ids[2]])
        // Spam click: the cursor is still over slot 0, which now hosts the displaced neighbor.
        state.moveTemplateRight(ids[1], in: rowId)
        #expect(state.rows.first!.templates.map(\.id) == [ids[1], ids[2], ids[0]], "Second rapid click should keep moving the first template, not swap back")
    }

    @Test func oppositeDirectionClickIsNotRedirectedToLastMovedTemplate() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let rowId = state.rows.first!.id
        let ids = state.rows.first!.templates.map(\.id)

        state.moveTemplateRight(ids[1], in: rowId)
        #expect(state.rows.first!.templates.map(\.id) == [ids[0], ids[2], ids[1]])
        state.moveTemplateLeft(ids[2], in: rowId)
        #expect(state.rows.first!.templates.map(\.id) == [ids[2], ids[0], ids[1]], "A different-direction click targets the clicked template itself")
    }

    @Test func moveContinuationExpiresAfterWindow() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let rowId = state.rows.first!.id
        let ids = state.rows.first!.templates.map(\.id)

        state.moveTemplateRight(ids[0], in: rowId)
        let c = try #require(state.templateMoveContinuation)
        state.templateMoveContinuation = TemplateMoveContinuation(
            rowId: c.rowId,
            movedTemplateId: c.movedTemplateId,
            displacedTemplateId: c.displacedTemplateId,
            toRight: c.toRight,
            at: Date(timeIntervalSinceNow: -1)
        )
        state.moveTemplateRight(ids[1], in: rowId)
        #expect(state.rows.first!.templates.map(\.id) == ids, "A click after the window moves the clicked template itself")
    }

    @Test func undoClearsMoveContinuation() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let undoManager = state.undoManager!
        let rowId = state.rows.first!.id
        let ids = state.rows.first!.templates.map(\.id)

        state.moveTemplateRight(ids[0], in: rowId)
        undoManager.undo()
        #expect(state.rows.first!.templates.map(\.id) == ids)
        // A rapid same-direction click after undo must not replay the undone move.
        state.moveTemplateRight(ids[1], in: rowId)
        #expect(state.rows.first!.templates.map(\.id) == [ids[0], ids[2], ids[1]], "Click after undo targets the clicked template, not the previously moved one")
    }
}
