#if os(iOS)
import UIKit

// Cross-platform aliases so the (macOS-first) codebase's `NSImage`/`NSColor`/`NSSize`
// references compile on iOS unchanged. The accompanying shim extensions add the slice of
// the AppKit API surface the code actually calls. AppKit-only drawing/window/event APIs
// are guarded with `#if os(macOS)` at their call sites instead.
typealias NSImage = UIImage
typealias NSColor = UIColor
typealias NSFont = UIFont
typealias NSSize = CGSize
typealias NSRect = CGRect
typealias NSPoint = CGPoint
#endif
