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

    var isChanged: Bool {
        description != (original.description ?? "")
            || keywords != (original.keywords ?? "")
            || promotionalText != (original.promotionalText ?? "")
            || whatsNew != (original.whatsNew ?? "")
            || marketingUrl != (original.marketingUrl ?? "")
            || supportUrl != (original.supportUrl ?? "")
    }

    func changedAttributes() -> [String: AnyEncodable] {
        var changes: [String: AnyEncodable] = [:]
        if description != (original.description ?? "") { changes["description"] = AnyEncodable(description) }
        if keywords != (original.keywords ?? "") { changes["keywords"] = AnyEncodable(keywords) }
        if promotionalText != (original.promotionalText ?? "") { changes["promotionalText"] = AnyEncodable(promotionalText) }
        if whatsNew != (original.whatsNew ?? "") { changes["whatsNew"] = AnyEncodable(whatsNew) }
        if marketingUrl != (original.marketingUrl ?? "") { changes["marketingUrl"] = AnyEncodable(marketingUrl) }
        if supportUrl != (original.supportUrl ?? "") { changes["supportUrl"] = AnyEncodable(supportUrl) }
        return changes
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

    var isChanged: Bool {
        name != (original.name ?? "")
            || subtitle != (original.subtitle ?? "")
            || privacyPolicyUrl != (original.privacyPolicyUrl ?? "")
    }

    func changedAttributes() -> [String: AnyEncodable] {
        var changes: [String: AnyEncodable] = [:]
        if name != (original.name ?? "") { changes["name"] = AnyEncodable(name) }
        if subtitle != (original.subtitle ?? "") { changes["subtitle"] = AnyEncodable(subtitle) }
        if privacyPolicyUrl != (original.privacyPolicyUrl ?? "") { changes["privacyPolicyUrl"] = AnyEncodable(privacyPolicyUrl) }
        return changes
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
