import Foundation

/// The localized App Store fields the wizard and MCP edit, with App Store Connect's length limits.
nonisolated enum ASCMetadataField: String, CaseIterable {
    case description, keywords, promotionalText, whatsNew, marketingUrl, supportUrl
    case name, subtitle, privacyPolicyUrl

    /// The App Store Connect attribute.
    var attribute: String { rawValue }

    /// The MCP argument key: the attribute in snake case.
    var argumentKey: String {
        rawValue.reduce(into: "") { key, character in
            key += character.isUppercase ? "_\(character.lowercased())" : String(character)
        }
    }

    var limit: Int? {
        switch self {
        case .name, .subtitle: 30
        case .keywords: 100
        case .promotionalText: 170
        case .description, .whatsNew: 4000
        case .marketingUrl, .supportUrl, .privacyPolicyUrl: nil
        }
    }

    /// Shared by every version of the app rather than written per version.
    var isAppInfo: Bool {
        switch self {
        case .name, .subtitle, .privacyPolicyUrl: true
        default: false
        }
    }

    var isURL: Bool {
        switch self {
        case .marketingUrl, .supportUrl, .privacyPolicyUrl: true
        default: false
        }
    }

    func exceedsLimit(_ value: String) -> Bool {
        limit.map { value.count > $0 } ?? false
    }
}
