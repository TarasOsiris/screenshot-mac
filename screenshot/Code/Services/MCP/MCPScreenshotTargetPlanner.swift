#if os(macOS)
import Foundation

/// The upload wizard's row and locale picks, made automatically for an agent.
enum MCPScreenshotTargetPlanner {
    static func targets(
        version: ASCAppStoreVersion,
        remoteLocalizations: [ASCAppStoreVersionLocalization],
        rows: [ScreenshotRow],
        localeCodes: [String]
    ) -> (targets: [ASCUploadTarget], issues: [String]) {
        var targets: [ASCUploadTarget] = []
        var issues: [String] = []
        var claimedSetKeys = Set<String>()
        let assigned = ASCLocaleMatcher.assign(appCodes: localeCodes, to: remoteLocalizations)
        for code in localeCodes where assigned[code, default: []].isEmpty {
            issues.append("Skipped \(version.id) · \(code): no unambiguous App Store localization mapping.")
        }
        for row in rows {
            guard !row.excludeFromAppStoreConnect else {
                issues.append("Skipped row \(row.id.uuidString): excluded from App Store Connect.")
                continue
            }
            guard row.isOriginal else {
                issues.append("Skipped row \(row.id.uuidString): belongs to an A/B variant, not the product page.")
                continue
            }
            guard let displayType = ASCDisplayType.detect(width: row.templateWidth, height: row.templateHeight) else {
                issues.append("Skipped row \(row.id.uuidString): its \(Int(row.templateWidth))×\(Int(row.templateHeight)) display type is ambiguous or unsupported.")
                continue
            }
            guard displayType.accepts(platform: version.attributes.ascPlatform) else {
                issues.append("Skipped row \(row.id.uuidString) for version \(version.id): \(displayType.label) is incompatible with \(version.attributes.displayPlatform ?? "the version platform").")
                continue
            }
            let candidates = localeCodes.flatMap { code in
                assigned[code, default: []].map {
                    ASCUploadLocalization(id: $0.id, label: $0.attributes.locale, localeCode: code)
                }
            }
            let localizations = candidates.filter { localization in
                let key = "\(localization.id)|\(displayType.appStoreConnectValue)"
                guard !claimedSetKeys.contains(key) else {
                    issues.append("Skipped row \(row.id.uuidString) · \(localization.label): another row already targets this display-type set.")
                    return false
                }
                claimedSetKeys.insert(key)
                return true
            }
            guard !localizations.isEmpty else { continue }
            targets.append(ASCUploadTarget(
                versionId: version.id,
                versionLabel: "\(version.attributes.displayPlatform ?? "App Store") · Version \(version.attributes.versionString)",
                parentKind: .versionLocalization,
                rowId: row.id,
                rowLabel: row.label.isEmpty ? "Row" : row.label,
                rowSize: row.templateSize,
                displayType: displayType,
                localizations: localizations,
                templateCount: row.templates.count
            ))
        }
        return (targets, issues)
    }
}
#endif
