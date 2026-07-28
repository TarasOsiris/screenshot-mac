import SwiftUI

/// Severity of a pre-flight upload validation issue, shared by the App Store Connect and
/// Google Play upload validators.
nonisolated enum UploadIssueSeverity {
    case error, warning

    var tint: Color { self == .error ? .red : .orange }
}

/// A single pre-flight validation finding for a store upload.
///
/// `demoDowngradable` marks issues App Store Connect softens to warnings in demo mode; Google Play
/// softens its per-row issues wholesale instead and leaves this false. `scoped(to:)` is used by the
/// App Store Connect flow, which groups issues under a per-version destination.
nonisolated struct UploadIssue: Identifiable {
    let severity: UploadIssueSeverity
    let scope: String?
    let message: String
    let hint: String?
    let demoDowngradable: Bool

    // Stable identity so ForEach does not re-diff the whole panel every render.
    var id: String { "\(severity)|\(scope ?? "")|\(message)" }

    init(
        severity: UploadIssueSeverity,
        scope: String? = nil,
        message: String,
        hint: String? = nil,
        demoDowngradable: Bool = false
    ) {
        self.severity = severity
        self.scope = scope
        self.message = message
        self.hint = hint
        self.demoDowngradable = demoDowngradable
    }

    func with(severity: UploadIssueSeverity) -> UploadIssue {
        UploadIssue(severity: severity, scope: scope, message: message, hint: hint, demoDowngradable: demoDowngradable)
    }

    /// Prefix the scope with an outer destination label (App Store Connect groups issues by version).
    func scoped(to destination: String) -> UploadIssue {
        let combinedScope = scope.map { "\(destination) · \($0)" } ?? destination
        return UploadIssue(severity: severity, scope: combinedScope, message: message, hint: hint, demoDowngradable: demoDowngradable)
    }
}

nonisolated extension Array where Element == UploadIssue {
    var hasErrors: Bool { contains { $0.severity == .error } }
}

/// Step counter driving the upload progress UI, shared by both store upload services.
nonisolated struct UploadProgress {
    var totalSteps: Int
    var completedSteps: Int
    var currentLabel: String
}
