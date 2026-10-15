import Foundation

/// Editable copies of a version's and an app's localized metadata, each tracking what
/// changed against what App Store Connect returned so only edits are PATCHed.
struct ASCVersionLocaleDraft: Identifiable {
    let id: String
    let versionId: String
    let locale: String
    var description: String
    var keywords: String
    var promotionalText: String
    var whatsNew: String
    var marketingUrl: String
    var supportUrl: String
    var original: ASCAppStoreVersionLocalization.Attributes

    static let fields = ASCMetadataField.allCases.filter { !$0.isAppInfo }

    subscript(field: ASCMetadataField) -> String {
        get { self[keyPath: Self.path(field)] }
        set { self[keyPath: Self.path(field)] = newValue }
    }

    private static func path(_ field: ASCMetadataField) -> WritableKeyPath<Self, String> {
        switch field {
        case .description: \.description
        case .keywords: \.keywords
        case .promotionalText: \.promotionalText
        case .whatsNew: \.whatsNew
        case .marketingUrl: \.marketingUrl
        case .supportUrl: \.supportUrl
        case .name, .subtitle, .privacyPolicyUrl: preconditionFailure("\(field) is an app info field")
        }
    }

    private func originalValue(_ field: ASCMetadataField) -> String {
        switch field {
        case .description: original.description ?? ""
        case .keywords: original.keywords ?? ""
        case .promotionalText: original.promotionalText ?? ""
        case .whatsNew: original.whatsNew ?? ""
        case .marketingUrl: original.marketingUrl ?? ""
        case .supportUrl: original.supportUrl ?? ""
        case .name, .subtitle, .privacyPolicyUrl: ""
        }
    }

    var isChanged: Bool { Self.fields.contains { self[$0] != originalValue($0) } }
    var exceedsLimits: Bool { Self.fields.contains { $0.exceedsLimit(self[$0]) } }

    func changedAttributes() -> [String: AnyEncodable] {
        Self.fields.reduce(into: [:]) { changes, field in
            if self[field] != originalValue(field) { changes[field.attribute] = AnyEncodable(self[field]) }
        }
    }

    mutating func markSaved() {
        original = ASCAppStoreVersionLocalization.Attributes(
            locale: locale,
            description: description,
            keywords: keywords,
            promotionalText: promotionalText,
            whatsNew: whatsNew,
            marketingUrl: marketingUrl,
            supportUrl: supportUrl
        )
    }
}

struct ASCAppInfoLocaleDraft: Identifiable {
    let id: String
    let locale: String
    var name: String
    var subtitle: String
    var privacyPolicyUrl: String
    var original: ASCAppInfoLocalization.Attributes

    static let fields = ASCMetadataField.allCases.filter(\.isAppInfo)

    subscript(field: ASCMetadataField) -> String {
        get { self[keyPath: Self.path(field)] }
        set { self[keyPath: Self.path(field)] = newValue }
    }

    private static func path(_ field: ASCMetadataField) -> WritableKeyPath<Self, String> {
        switch field {
        case .name: \.name
        case .subtitle: \.subtitle
        case .privacyPolicyUrl: \.privacyPolicyUrl
        default: preconditionFailure("\(field) is a version field")
        }
    }

    private func originalValue(_ field: ASCMetadataField) -> String {
        switch field {
        case .name: original.name ?? ""
        case .subtitle: original.subtitle ?? ""
        case .privacyPolicyUrl: original.privacyPolicyUrl ?? ""
        default: ""
        }
    }

    var isChanged: Bool { Self.fields.contains { self[$0] != originalValue($0) } }
    var exceedsLimits: Bool { Self.fields.contains { $0.exceedsLimit(self[$0]) } }

    func changedAttributes() -> [String: AnyEncodable] {
        Self.fields.reduce(into: [:]) { changes, field in
            if self[field] != originalValue(field) { changes[field.attribute] = AnyEncodable(self[field]) }
        }
    }

    mutating func markSaved() {
        original = ASCAppInfoLocalization.Attributes(
            locale: locale,
            name: name,
            subtitle: subtitle,
            privacyPolicyUrl: privacyPolicyUrl,
            privacyPolicyText: original.privacyPolicyText,
            privacyChoicesUrl: original.privacyChoicesUrl
        )
    }
}
