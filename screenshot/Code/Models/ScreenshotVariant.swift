import Foundation

/// An A/B alternative to the Original rows; rows opt in via `ScreenshotRow.variantId`.
nonisolated struct ScreenshotVariant: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    /// Kept per variant so deleting one doesn't recolour the rest.
    var colorIndex: Int?

    init(id: UUID = UUID(), name: String, colorIndex: Int? = nil) {
        self.id = id
        self.name = name
        self.colorIndex = colorIndex
    }

    enum CodingKeys: String, CodingKey {
        case id, name = "n", colorIndex = "c"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        colorIndex = try c.decodeIfPresent(Int.self, forKey: .colorIndex)
    }

    static let maxNameLength = 50
    static let colorSlots = 6
}

extension Array where Element == ScreenshotVariant {
    func variant(withId id: UUID?) -> ScreenshotVariant? {
        guard let id else { return nil }
        return first { $0.id == id }
    }

    /// Recreates variants rows still name (hand edit, iCloud merge), keeping those rows off the product page.
    func recoveringVariants(namedBy rows: [ScreenshotRow]) -> [ScreenshotVariant] {
        guard FeatureFlags.abTesting else { return self }
        var result = self
        var known = Set(map(\.id))
        for row in rows {
            guard let id = row.variantId, known.insert(id).inserted else { continue }
            result.append(ScreenshotVariant(
                id: id,
                name: result.uniqueName(String(localized: "Recovered Variant")),
                colorIndex: result.nextColorIndex(among: ScreenshotVariant.colorSlots)
            ))
        }
        return result
    }

    /// `proposed`, numbered if another variant (or the Original) already uses it, ignoring case.
    func uniqueName(_ proposed: String, excluding id: UUID? = nil) -> String {
        var taken = Set(filter { $0.id != id }.map { $0.name.lowercased() })
        taken.insert(String(localized: "Original").lowercased())
        taken.insert("original")
        guard taken.contains(proposed.lowercased()) else { return proposed }
        var suffix = 2
        while taken.contains("\(proposed) \(suffix)".lowercased()) { suffix += 1 }
        return "\(proposed) \(suffix)"
    }

    /// The first free colour slot; a variant saved before slots existed holds its position, as the palette draws it.
    func nextColorIndex(among count: Int) -> Int {
        let taken = Set(enumerated().map { position, variant in (variant.colorIndex ?? position) % count })
        return (0..<count).first { !taken.contains($0) } ?? self.count % count
    }

    /// The first free "Variant B", "Variant C", … — B because the Original is implicitly A.
    func nextDefaultName() -> String {
        let taken = Set(map { $0.name.lowercased() })
        for letter in "BCDEFGHIJKLMNOPQRSTUVWXYZ".map(String.init) {
            let candidate = String(localized: "Variant \(letter)")
            if !taken.contains(candidate.lowercased()) { return candidate }
        }
        return String(localized: "Variant \(count + 2)")
    }
}

extension Array where Element == ScreenshotRow {
    /// The rows tagged with `variantId`; nil is the Original.
    func inVariant(_ variantId: UUID?) -> [ScreenshotRow] {
        filter { $0.activeVariantId == variantId }
    }
}

/// Decodes to nil instead of throwing, so one bad element can't fail the array around it.
nonisolated struct LossyDecodable<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}
