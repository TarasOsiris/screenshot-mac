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
}
