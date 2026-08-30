#if os(iOS)
import UIKit
#endif

/// The device class the app is running on, as a stable analytics/diagnostics vocabulary.
///
/// iPadOS and iPhone ship from one target, so a compile-time `#if` cannot tell them apart — only
/// the runtime idiom can. Before this existed, every iOS build reported itself as iPad.
nonisolated enum PlatformDeviceClass: String, CaseIterable {
    case macos
    case ipados
    case iphone

    @MainActor static var current: PlatformDeviceClass {
        #if os(macOS)
        .macos
        #else
        UIDevice.current.userInterfaceIdiom == .phone ? .iphone : .ipados
        #endif
    }
}
