import Foundation

/// Which job the App Store Connect wizard is doing. `.screenshots` runs every step
/// (app → versions → metadata → plan → upload); `.metadata` stops after saving metadata,
/// so it also accepts versions that are locked for screenshots but still editable.
nonisolated enum ASCFlowMode {
    case screenshots
    case metadata
}

extension ASCAppStoreVersion {
    nonisolated func isSelectable(for mode: ASCFlowMode) -> Bool {
        switch mode {
        case .screenshots: isScreenshotUploadable
        case .metadata: isEditable
        }
    }
}

extension ASCAppWithVersions {
    nonisolated func hasSelectableVersion(for mode: ASCFlowMode) -> Bool {
        versions.contains { $0.isSelectable(for: mode) }
    }
}
