import Foundation

/// The App Store Connect wizard's screens, in order.
nonisolated enum ASCUploadStep: Hashable {
    case pickingApp
    case pickingVersion
    case editingMetadata
    case configuringPlan
    case reviewingChanges
    case uploading
    case done
}
