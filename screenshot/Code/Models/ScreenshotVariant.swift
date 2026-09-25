import Foundation

/// An A/B alternative to the Original rows; rows opt in via `ScreenshotRow.variantId`.
nonisolated struct ScreenshotVariant: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }

    enum CodingKeys: String, CodingKey {
        case id, name = "n"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
    }

    static let maxNameLength = 50
}

extension Array where Element == ScreenshotVariant {
    func variant(withId id: UUID?) -> ScreenshotVariant? {
        guard let id else { return nil }
        return first { $0.id == id }
    }

    /// The first free "Variant B", "Variant C", … — B because the Original is implicitly A.
    func nextDefaultName() -> String {
        let taken = Set(map(\.name))
        for letter in "BCDEFGHIJKLMNOPQRSTUVWXYZ".map(String.init) {
            let candidate = String(localized: "Variant \(letter)")
            if !taken.contains(candidate) { return candidate }
        }
        return String(localized: "Variant \(count + 2)")
    }
}

extension Array where Element == ScreenshotRow {
    /// The rows tagged with `variantId`; nil is the Original.
    func inVariant(_ variantId: UUID?) -> [ScreenshotRow] {
        filter { $0.variantId == variantId }
    }
}
