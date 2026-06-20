import Foundation
import SwiftUI

struct GPUploadIssue: Identifiable {
    enum Severity {
        case error, warning
        var tint: Color { self == .error ? .red : .orange }
    }
    let severity: Severity
    let scope: String?
    let message: String
    let hint: String?

    var id: String { "\(severity)|\(scope ?? "")|\(message)" }

    init(severity: Severity, scope: String? = nil, message: String, hint: String? = nil) {
        self.severity = severity
        self.scope = scope
        self.message = message
        self.hint = hint
    }

    func with(severity: Severity) -> GPUploadIssue {
        GPUploadIssue(severity: severity, scope: scope, message: message, hint: hint)
    }
}

enum GooglePlayUploadValidator {
    /// Pre-flight checks that need no rendering or network. In demo mode the package name is
    /// irrelevant (no traffic) and per-row issues are softened to warnings so the flow stays walkable.
    static func validate(
        packageName: String,
        plans: [UploadToGooglePlayView.GPRowPlan],
        isDemoMode: Bool
    ) -> [GPUploadIssue] {
        var issues: [GPUploadIssue] = []

        if !isDemoMode {
            let trimmed = packageName.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                issues.append(GPUploadIssue(
                    severity: .error,
                    message: "Enter the app's package name (application ID).",
                    hint: "For example: com.example.myapp"
                ))
            } else if !isValidPackageName(trimmed) {
                issues.append(GPUploadIssue(
                    severity: .error,
                    message: "\"\(trimmed)\" doesn't look like a valid package name.",
                    hint: "Use the reverse-DNS application ID, e.g. com.example.myapp"
                ))
            }
        }

        if plans.isEmpty {
            issues.append(GPUploadIssue(
                severity: .error,
                message: "This project has no rows to upload.",
                hint: "Add a row in the editor before running the upload."
            ))
            return issues
        }

        let enabledPlans = plans.filter { $0.isEnabled }
        if enabledPlans.isEmpty {
            issues.append(GPUploadIssue(
                severity: .error,
                message: "Enable at least one row to upload."
            ))
            return issues
        }

        var perRow: [GPUploadIssue] = []
        var seenTargets: [String: String] = [:]

        for plan in enabledPlans {
            let rowName = plan.rowLabel.isEmpty ? "Row" : plan.rowLabel
            let sizeLabel = "\(Int(plan.rowSize.width))×\(Int(plan.rowSize.height))"

            if !GPImageType.accepts(width: plan.rowSize.width, height: plan.rowSize.height) {
                perRow.append(GPUploadIssue(
                    severity: .error,
                    scope: rowName,
                    message: "Row size \(sizeLabel) is outside Google Play's limits.",
                    hint: "Screenshots must be 320–3840 px per edge with an aspect ratio no greater than 2:1."
                ))
            }

            if plan.templateCount < GPUploadLimits.minScreenshotsPerType {
                perRow.append(GPUploadIssue(
                    severity: .error,
                    scope: rowName,
                    message: "Google Play requires at least \(GPUploadLimits.minScreenshotsPerType) screenshots per type; this row has \(plan.templateCount).",
                    hint: "Add more screenshot columns to this row."
                ))
            }
            if plan.templateCount > GPUploadLimits.maxScreenshotsPerType {
                perRow.append(GPUploadIssue(
                    severity: .error,
                    scope: rowName,
                    message: "Google Play allows at most \(GPUploadLimits.maxScreenshotsPerType) screenshots per type; this row has \(plan.templateCount).",
                    hint: "Remove columns to bring the count to \(GPUploadLimits.maxScreenshotsPerType) or fewer."
                ))
            }

            let enabledLocales = plan.localeTargets.filter { $0.isEnabled }
            if enabledLocales.isEmpty {
                perRow.append(GPUploadIssue(
                    severity: .error,
                    scope: rowName,
                    message: "Enable at least one language to upload to."
                ))
            }

            var reportedCollisionPartners: Set<String> = []
            for locale in enabledLocales {
                let key = "\(locale.playLanguageCode)|\(plan.selectedImageType.apiValue)"
                if let partner = seenTargets[key] {
                    if reportedCollisionPartners.insert(partner).inserted {
                        perRow.append(GPUploadIssue(
                            severity: .error,
                            scope: rowName,
                            message: "This row uploads \(plan.selectedImageType.label) for \(locale.playLanguageCode) to the same place as \(partner).",
                            hint: "Disable one of these rows or pick a different image type."
                        ))
                    }
                } else {
                    seenTargets[key] = rowName
                }
            }
        }

        issues.append(contentsOf: isDemoMode ? perRow.map { $0.with(severity: .warning) } : perRow)
        return issues
    }

    /// Reverse-DNS application id: ≥2 segments, each starting with a letter, letters/digits/underscore.
    static func isValidPackageName(_ name: String) -> Bool {
        let segments = name.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2 else { return false }
        return segments.allSatisfy { segment in
            let s = String(segment)
            let range = NSRange(s.startIndex..<s.endIndex, in: s)
            return packageSegmentRegex.firstMatch(in: s, range: range) != nil
        }
    }

    // Compiled once — `validate` runs on every SwiftUI render, so don't recompile per call.
    private static let packageSegmentRegex = try! NSRegularExpression(pattern: "^[a-zA-Z][a-zA-Z0-9_]*$")
}

extension Array where Element == GPUploadIssue {
    var hasErrors: Bool { contains { $0.severity == .error } }
}
