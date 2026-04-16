import Foundation
import SwiftUI

// Per App Store Connect screenshot specifications: 3–10 assets per display type.
enum ASCUploadLimits {
    static let minScreenshotsPerSet = 3
    static let maxScreenshotsPerSet = 10
}

struct ASCUploadIssue: Identifiable {
    enum Severity {
        case error, warning

        var tint: Color { self == .error ? .red : .orange }
    }
    let severity: Severity
    let scope: String?
    let message: String
    let hint: String?

    // Stable identity so ForEach does not re-diff the whole panel every render.
    var id: String { "\(severity)|\(scope ?? "")|\(message)" }

    init(severity: Severity, scope: String? = nil, message: String, hint: String? = nil) {
        self.severity = severity
        self.scope = scope
        self.message = message
        self.hint = hint
    }
}

enum ASCUploadValidator {
    /// Runs all pre-flight checks that don't require rendering or network calls.
    static func validate(
        version: ASCAppStoreVersion,
        plans: [UploadToAppStoreConnectView.RowPlan]
    ) -> [ASCUploadIssue] {
        var issues: [ASCUploadIssue] = []

        if !version.isEditable {
            issues.append(ASCUploadIssue(
                severity: .error,
                message: "Version \(version.attributes.versionString) is \(version.attributes.displayState). Screenshots can only be changed when the version is editable.",
                hint: "Create a new version in App Store Connect, or wait for this one to return to an editable state."
            ))
        }

        let enabledPlans = plans.filter { $0.isEnabled }
        if enabledPlans.isEmpty {
            issues.append(ASCUploadIssue(
                severity: .error,
                message: "Enable at least one row to upload."
            ))
            return issues
        }

        for plan in enabledPlans {
            let rowName = plan.rowLabel.isEmpty ? "Row" : plan.rowLabel
            let sizeLabel = "\(Int(plan.rowSize.width))×\(Int(plan.rowSize.height))"

            guard let displayType = plan.selectedDisplayType else {
                issues.append(ASCUploadIssue(
                    severity: .error,
                    scope: rowName,
                    message: "Pick a display type for this row (\(sizeLabel)).",
                    hint: "Use the \"Display type\" picker above."
                ))
                continue
            }

            if !displayType.accepts(width: plan.rowSize.width, height: plan.rowSize.height) {
                let accepted = displayType.acceptedPortraitSizes
                    .map { "\($0.0)×\($0.1)" }
                    .joined(separator: ", ")
                issues.append(ASCUploadIssue(
                    severity: .error,
                    scope: rowName,
                    message: "Row size \(sizeLabel) isn't accepted by App Store Connect for \(displayType.label).",
                    hint: accepted.isEmpty
                        ? "Pick a different display type."
                        : "Resize the row to one of: \(accepted), or pick a matching display type."
                ))
            }

            if plan.templateCount < ASCUploadLimits.minScreenshotsPerSet {
                issues.append(ASCUploadIssue(
                    severity: .error,
                    scope: rowName,
                    message: "App Store Connect requires at least \(ASCUploadLimits.minScreenshotsPerSet) screenshots per display type; this row has \(plan.templateCount).",
                    hint: "Add more screenshot columns to this row."
                ))
            }
            if plan.templateCount > ASCUploadLimits.maxScreenshotsPerSet {
                issues.append(ASCUploadIssue(
                    severity: .error,
                    scope: rowName,
                    message: "App Store Connect allows at most \(ASCUploadLimits.maxScreenshotsPerSet) screenshots per display type; this row has \(plan.templateCount).",
                    hint: "Remove columns to bring the count to \(ASCUploadLimits.maxScreenshotsPerSet) or fewer."
                ))
            }

            let activeLocaleCount = plan.localeTargets.filter { $0.isEnabled && $0.selectedASCLocalizationId != nil }.count
            if activeLocaleCount == 0 {
                issues.append(ASCUploadIssue(
                    severity: .error,
                    scope: rowName,
                    message: "Pick at least one App Store locale to upload to.",
                    hint: "Enable a locale checkbox and choose an App Store locale."
                ))
            }

            let unmatched = plan.localeTargets.filter { $0.isEnabled && $0.candidates.isEmpty }
            for target in unmatched {
                issues.append(ASCUploadIssue(
                    severity: .warning,
                    scope: rowName,
                    message: "No App Store locale matches \(target.appLocaleLabel) on this version.",
                    hint: "Add the locale in App Store Connect, or disable this locale here."
                ))
            }
        }

        return issues
    }
}

extension Array where Element == ASCUploadIssue {
    var hasErrors: Bool { contains { $0.severity == .error } }
}
