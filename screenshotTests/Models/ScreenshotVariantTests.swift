import Foundation
@testable import Screenshot_Bro
import Testing

@MainActor
struct ScreenshotVariantTests {

    @Test func projectDataWithoutVariantsDecodes() throws {
        let json = #"{"r":[],"m":0}"#
        let data = try JSONDecoder().decode(ProjectData.self, from: Data(json.utf8))
        #expect(data.variants.isEmpty)
    }

    @Test func projectDataOmitsEmptyVariantsKey() throws {
        let encoded = try JSONEncoder().encode(ProjectData(rows: []))
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["v"] == nil)
    }

    @Test func variantsRoundTrip() throws {
        let variant = ScreenshotVariant(name: "Dark hero")
        var row = ScreenshotRow()
        row.variantId = variant.id
        let original = ProjectData(rows: [row, ScreenshotRow()], variants: [variant])

        let decoded = try JSONDecoder().decode(ProjectData.self, from: JSONEncoder().encode(original))

        #expect(decoded.variants == [variant])
        #expect(decoded.rows.map(\.variantId) == [variant.id, nil])
    }

    @Test func originalRowOmitsVariantKey() throws {
        let encoded = try JSONEncoder().encode(ScreenshotRow())
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["vr"] == nil)
    }

    @Test func nextDefaultNameSkipsTakenLetters() {
        let taken = [ScreenshotVariant(name: String(localized: "Variant B"))]
        #expect(taken.nextDefaultName() == String(localized: "Variant C"))
        #expect([ScreenshotVariant]().nextDefaultName() == String(localized: "Variant B"))
    }

    @Test func variantFilterFallsBackToAllForUnknownVariant() {
        let variant = ScreenshotVariant(name: "B")
        #expect(EditorVariantFilter.variant(variant.id).resolved(in: [variant]) == .variant(variant.id))
        #expect(EditorVariantFilter.variant(UUID()).resolved(in: [variant]) == .all)
        #expect(EditorVariantFilter.variant(nil).resolved(in: [variant]) == .variant(nil))
    }

    @Test func variantFilterFallsBackToAllOnceNoVariantsRemain() {
        #expect(EditorVariantFilter.variant(nil).resolved(in: []) == .all)
        #expect(EditorVariantFilter.variant(UUID()).resolved(in: []) == .all)
    }

    @Test func nextColorSlotSkipsAVariantThatPredatesSlots() {
        let legacy = ScreenshotVariant(name: "B")
        #expect([legacy].nextColorIndex(among: 6) == 1)
        #expect([ScreenshotVariant(name: "B", colorIndex: 0), ScreenshotVariant(name: "C", colorIndex: 2)].nextColorIndex(among: 6) == 1)
    }

    @Test func rowsNamingAMissingVariantStayOffTheProductPage() {
        let variant = ScreenshotVariant(name: "B")
        let orphanId = UUID()
        let kept = ScreenshotRow(variantId: variant.id)
        let orphan = ScreenshotRow(variantId: orphanId)

        let document = ProjectDocument(ProjectData(rows: [kept, orphan], variants: [variant]))

        #expect(document.rows.map(\.variantId) == [variant.id, orphanId])
        #expect(document.variants.map(\.id) == [variant.id, orphanId])
        #expect(document.variants.last?.name == String(localized: "Recovered Variant"))
    }

    @Test func variantFolderNamesNeverCollide() {
        let a = ScreenshotVariant(name: "A/B")
        let b = ScreenshotVariant(name: "A:B")
        let original = ScreenshotVariant(name: "original")

        let names = ExportFileNaming.variantFolderNames([a, b, original])

        let values = Array(names.values).map { $0.lowercased() }
        #expect(Set(values).count == values.count)
        #expect(names[nil] == String(localized: "Original"))
    }

    @Test func aMalformedVariantEntryDoesNotMakeTheProjectUnreadable() throws {
        let good = ScreenshotVariant(name: "B")
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(ProjectData(rows: [ScreenshotRow()]))) as? [String: Any]
        )
        object["v"] = [["id": "not-a-uuid", "n": "Broken"], ["id": good.id.uuidString, "n": "B"]]
        var rows = try #require(object["r"] as? [[String: Any]])
        rows[0]["vr"] = "garbage"
        object["r"] = rows

        let data = try JSONDecoder().decode(ProjectData.self, from: JSONSerialization.data(withJSONObject: object))

        #expect(data.variants.map(\.id) == [good.id])
        #expect(data.rows.first?.variantId == nil)
    }

    #if os(macOS)
    @Test func templatesKeepOnlyTheOriginalRows() {
        let variant = ScreenshotVariant(name: "B")
        let original = ScreenshotRow()
        let copy = ScreenshotRow(variantId: variant.id, originRowId: original.id)

        let stripped = DebugTemplateService.withoutVariants(ProjectData(rows: [original, copy], variants: [variant]))

        #expect(stripped.rows.map(\.id) == [original.id])
        #expect(stripped.variants.isEmpty)
    }
    #endif
}
