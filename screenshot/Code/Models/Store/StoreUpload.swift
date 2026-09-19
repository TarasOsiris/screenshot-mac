import Foundation

/// Severity of a pre-flight upload validation issue, shared by the App Store Connect and
/// Google Play upload validators.
nonisolated enum UploadIssueSeverity {
    case error, warning
}

/// The plan change that clears an issue, when one change obviously does. Declarative rather than
/// a closure so the validators stay pure functions of the plan and the flow model remains the only
/// thing that mutates it.
nonisolated struct UploadIssueFix: Equatable {
    enum Action: Equatable {
        /// Enable the listed app locales and tick every store locale they match.
        case selectMatchingStoreLocales
        /// Upload the row as the display type detected from its size.
        case useDetectedAssetType
    }

    let action: Action
    /// Which version's copy of the row to change — the same row appears in every destination.
    let destinationId: String?
    let rowId: UUID
    let appLocaleCodes: [String]

    init(_ action: Action, destinationId: String? = nil, rowId: UUID, appLocaleCodes: [String] = []) {
        self.action = action
        self.destinationId = destinationId
        self.rowId = rowId
        self.appLocaleCodes = appLocaleCodes
    }
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
    let fix: UploadIssueFix?

    // Stable identity so ForEach does not re-diff the whole panel every render.
    var id: String { "\(severity)|\(scope ?? "")|\(message)" }

    init(
        severity: UploadIssueSeverity,
        scope: String? = nil,
        message: String,
        hint: String? = nil,
        demoDowngradable: Bool = false,
        fix: UploadIssueFix? = nil
    ) {
        self.severity = severity
        self.scope = scope
        self.message = message
        self.hint = hint
        self.demoDowngradable = demoDowngradable
        self.fix = fix
    }

    func with(severity: UploadIssueSeverity) -> UploadIssue {
        UploadIssue(severity: severity, scope: scope, message: message, hint: hint, demoDowngradable: demoDowngradable, fix: fix)
    }

    /// Prefix the scope with an outer destination label (App Store Connect groups issues by version).
    func scoped(to destination: String) -> UploadIssue {
        let combinedScope = scope.map { "\(destination) · \($0)" } ?? destination
        return UploadIssue(severity: severity, scope: combinedScope, message: message, hint: hint, demoDowngradable: demoDowngradable, fix: fix)
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
