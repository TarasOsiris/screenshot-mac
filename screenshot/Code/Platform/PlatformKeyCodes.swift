import Foundation

/// Virtual key codes the editor's key monitors match on. These are Carbon `kVK_*` values, not
/// app state — they were on `AppState` only because that is where the monitor lives, which meant
/// `QuickLookCoordinator` had to reach into the document object to read a key code.
nonisolated enum PlatformKeyCode {
    static let LeftArrow: UInt16 = 0x7B
    static let RightArrow: UInt16 = 0x7C
    static let DownArrow: UInt16 = 0x7D
    static let UpArrow: UInt16 = 0x7E
    static let Delete: UInt16 = 0x33
    static let ForwardDelete: UInt16 = 0x75
}
