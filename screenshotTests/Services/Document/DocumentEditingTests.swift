import Foundation
@testable import Screenshot_Bro
import SwiftUI
import Testing

/// The document logic the editor and MCP share, exercised without an `AppState`.
@MainActor
struct DocumentEditingTests {

    /// Records copies instead of touching disk; every copy succeeds.
    private final class RecordingCopier: ImageResourceCopying {
        var copies: [(from: String, to: String)] = []
        func copyImageResource(_ fileName: String, to newFileName: String) -> Bool {
            copies.append((fileName, newFileName))
            return true
        }
    }

    private let defaults = NewRowDefaults(size: (1242, 2688), templateCount: 3, deviceCategory: nil, deviceFrameId: nil)

    private func makeRow(templates: Int = 3) -> ScreenshotRow {
        ScreenshotRow.makeDefault(
            templateCount: templates,
            defaults: NewRowDefaults(size: (1000, 2000), templateCount: templates, deviceCategory: nil, deviceFrameId: nil)
        )
    }

    private func localeState(_ codes: String...) -> LocaleState {
        LocaleState(locales: codes.map { LocaleDefinition(code: $0, label: $0) }, activeLocaleCode: codes[0], overrides: [:])
    }

    private func textShape(_ text: String, key: String? = nil, x: CGFloat = 100) -> CanvasShapeModel {
        var shape = CanvasShapeModel(type: .text, x: x, y: 100, width: 300, height: 80)
        shape.text = text
        shape.translationKey = key
        return shape
    }

    // MARK: - Shapes

    @Test func deleteShapesOfTypeRemovesLockedOnesAndTheirOverridesAndImages() {
        var row = makeRow()
        var locked = CanvasShapeModel(type: .image, x: 0, y: 0, width: 100, height: 100)
        locked.displayImageFileName = "base.png"
        locked.isLocked = true
        let kept = CanvasShapeModel(type: .rectangle, x: 0, y: 0, width: 100, height: 100)
        row.shapes = [locked, kept]
        var rows = [row]
        var locales = localeState("en", "de")
        var override = ShapeLocaleOverride()
        override.overrideImageFileName = "de.png"
        locales.overrides["de"] = [locked.id.uuidString: override]

        let removed = DocumentEditing.deleteShapes(ofType: .image, inRowAt: 0, rows: &rows, localeState: &locales)

        #expect(removed.removedIds == [locked.id])
        #expect(Set(removed.imageCandidates) == ["base.png", "de.png"])
        #expect(rows[0].shapes.map(\.id) == [kept.id])
        #expect(locales.overrides["de"] == nil, "the deleted shape's override and the emptied locale entry go too")
    }

    @Test func aBaseLanguageEditReachesEveryMemberOfAReusedString() {
        var row = makeRow()
        row.shapes = [textShape("Old", key: "shared"), textShape("Old", key: "shared", x: 1100), textShape("Other")]
        var rows = [row]
        var locales = localeState("en", "de")
        var edited = rows[0].shapes[0]
        edited.text = "New"

        DocumentEditing.commitShapeEdit(edited, at: (0, 0), forLocaleCode: "en", rows: &rows, localeState: &locales)

        #expect(rows[0].shapes.map(\.text) == ["New", "New", "Other"])
    }

    @Test func aTranslatedEditStaysInItsLanguage() {
        var row = makeRow()
        row.shapes = [textShape("Hello", key: "shared"), textShape("Hello", key: "shared", x: 1100)]
        var rows = [row]
        var locales = localeState("en", "de")
        var edited = rows[0].shapes[0]
        edited.text = "Hallo"

        DocumentEditing.commitShapeEdit(edited, at: (0, 0), forLocaleCode: "de", rows: &rows, localeState: &locales)

        #expect(rows[0].shapes.map(\.text) == ["Hello", "Hello"], "the base text is untouched")
        #expect(locales.overrides["de"]?["shared"]?.text == "Hallo")
    }

    @Test func distributeSpacesShapesEvenly() {
        var row = makeRow()
        row.shapes = [0, 500, 100].map { CanvasShapeModel(type: .rectangle, x: $0, y: 0, width: 100, height: 100) }

        DocumentEditing.align(.distributeH, shapesAt: [0, 1, 2], in: &row)

        #expect(row.shapes.map(\.x) == [0, 500, 250])
    }

    @Test func duplicatingToTheRightSkipsEarlierColumnsAndCopiesImages() {
        var row = makeRow(templates: 3)
        var shape = CanvasShapeModel(type: .image, x: 1400, y: 0, width: 200, height: 200)
        shape.displayImageFileName = "shot.png"
        row.shapes = [shape]
        var locales = localeState("en")
        let copier = RecordingCopier()

        DocumentEditing.duplicateShapesToTemplates([shape], direction: .right, in: &row, localeState: &locales, resources: copier)

        #expect(row.shapes.count == 2)
        #expect(row.owningTemplateIndex(for: row.shapes[1]) == 2)
        #expect(copier.copies.map(\.from) == ["shot.png"])
        #expect(row.shapes[1].displayImageFileName == "\(row.shapes[1].id.uuidString).png")
    }

    @Test func aDroppedScreenshotPrefersARealFrameOverANearerAbstractOne() {
        var row = makeRow(templates: 1)
        let abstract = CanvasShapeModel(type: .device, x: 350, y: 850, width: 300, height: 300)
        var framed = CanvasShapeModel(type: .device, x: 0, y: 0, width: 300, height: 600)
        framed.deviceFrameId = "iphone17-black"
        row.shapes = [abstract, framed]

        #expect(DocumentEditing.existingDeviceShapeIndex(in: row, templateIndex: 0) == 1)
    }

    // MARK: - Rows

    @Test func resetRowKeepsIdentitySizeAndUploadSetting() {
        var row = makeRow()
        row.label = "Hero"
        row.isLabelManuallySet = true
        row.excludeFromAppStoreConnect = true
        var image = CanvasShapeModel(type: .image, x: 0, y: 0, width: 100, height: 100)
        image.displayImageFileName = "shot.png"
        row.shapes = [image, textShape("Title")]
        var rows = [row]
        var locales = localeState("en", "de")
        locales.overrides["de"] = [row.shapes[1].id.uuidString: ShapeLocaleOverride()]

        let freed = DocumentEditing.resetRow(at: 0, rows: &rows, localeState: &locales, defaults: defaults)

        #expect(rows[0].id == row.id)
        #expect(rows[0].label == "Hero")
        #expect(rows[0].templateWidth == 1000 && rows[0].templateHeight == 2000)
        #expect(rows[0].excludeFromAppStoreConnect)
        #expect(rows[0].shapes.allSatisfy { $0.type == .device } || rows[0].shapes.isEmpty)
        #expect(freed == ["shot.png"])
        #expect(locales.overrides.isEmpty)
    }

    @Test func aMoveSkipsRowsTheFilterHides() {
        let rows = (0..<4).map { _ in makeRow() }
        let visible: Set<UUID> = [rows[0].id, rows[3].id]

        #expect(DocumentEditing.rowMoveTarget(from: 3, up: true, in: rows) { visible.contains($0.id) } == 0)
        #expect(DocumentEditing.rowMoveTarget(from: 0, up: true, in: rows) == nil)
        #expect(DocumentEditing.rowMoveTarget(from: 1, up: false, in: rows) == 2)
    }

    // MARK: - Locales

    @Test func resetLocaleDropsItsOverridesButKeepsTheLanguage() {
        var row = makeRow()
        row.shapes = [textShape("Hi")]
        var rows = [row]
        var locales = localeState("en", "de")
        var override = ShapeLocaleOverride()
        override.overrideImageFileName = "de.png"
        locales.overrides["de"] = [row.shapes[0].id.uuidString: override]

        let freed = DocumentEditing.resetLocale("de", rows: &rows, localeState: &locales)

        #expect(freed == ["de.png"])
        #expect(locales.overrides["de"] == nil)
        #expect(locales.hasLocale("de"))

        locales.overrides["de"] = [row.shapes[0].id.uuidString: override]
        #expect(DocumentEditing.removeLocale("de", rows: &rows, localeState: &locales) == ["de.png"])
        #expect(!locales.hasLocale("de"))
    }

    @Test func aNewTranslationTakesBackAnEarlierAutoFit() {
        var row = makeRow()
        row.shapes = [textShape("Hi")]
        let rows = [row]
        var locales = localeState("en", "de")
        let key = row.shapes[0].id.uuidString
        var fitted = ShapeLocaleOverride()
        fitted.text = "Hallo"
        fitted = fitted.addingAutoFit(TextAutoFitContribution(addedHeight: 10, fontSize: 40))
        locales.overrides["de"] = [key: fitted]

        DocumentEditing.takeBackAutoFit(textKey: key, localeCode: "de", rows: rows, localeState: &locales)

        #expect(locales.overrides["de"]?[key]?.autoFit == nil)
        #expect(locales.overrides["de"]?[key]?.text == "Hallo")
    }
}
