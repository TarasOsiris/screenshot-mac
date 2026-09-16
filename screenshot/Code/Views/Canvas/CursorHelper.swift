import SwiftUI

/// Cross-platform cursor operations, and the single owner of the macOS cursor. macOS drives
/// `NSCursor`; on iPad nothing is ever applied (touch has no cursor), so call sites stay free of
/// `#if os(macOS)`.
///
/// Two slots, never a stack: what the pointer is *over* (`hover`) and what an in-flight gesture
/// *demands* (`hold`). A held cursor wins, so the hover-exit SwiftUI fires when a drag carries the
/// pointer off its handle can no longer revert the cursor mid-gesture — with a stack that exit
/// popped the drag's own cursor. Every write names its `Owner` and only that owner can take its
/// claim back, which is what a stack couldn't express: a handle torn down while hovered used to
/// strand its pushed cursor for good.
enum PlatformCursor {
    /// Named platform-neutrally so call sites and the iPad build never mention `NSCursor`.
    enum Kind: Equatable {
        case arrow
        case openHand
        case closedHand
        case rotate
        case resize(edge: ResizeEdge, rotation: Double)
    }

    enum Owner: Equatable {
        case canvas
        case resizeHandle(ResizeEdge)
        case rotateHandle
        case shapeBody
        case pan
    }

    /// What the pointer is over. Prefer the `cursorHover` modifier — it pairs this with the
    /// teardown clear that a view torn down mid-hover never gets from `onHover`.
    static func hover(_ kind: Kind?, for owner: Owner) {
        // A handle's hit area straddles the shape's edge, so the row's canvas hover fires while
        // the pointer is still on the knob. The layer that paints on top names the cursor.
        if kind != nil, let hovered, hovered.owner != owner, hovered.owner != .canvas { return }
        // A stale exit from a target the pointer has already left must not clear the new one.
        if kind == nil, hovered?.owner != owner { return }
        hovered = kind.map { (owner, $0) }
        apply()
    }

    /// Claims the cursor for the length of a gesture. Call it on *every* tick: AppKit resets the
    /// cursor as the pointer moves, so a one-shot set doesn't survive a drag.
    static func hold(_ kind: Kind, for owner: Owner) {
        held = (owner, kind)
        apply()
    }

    /// Owner-checked so one gesture's end can't drop a hold another took.
    static func release(_ owner: Owner) {
        guard held?.owner == owner else { return }
        held = nil
        apply()
    }

    /// A disappearing gesture target may receive no hover-exit or gesture-end callback.
    static func clear(_ owner: Owner) {
        if hovered?.owner == owner { hovered = nil }
        if held?.owner == owner { held = nil }
        apply()
    }

    static var resolvedKind: Kind { held?.kind ?? hovered?.kind ?? .arrow }

    #if DEBUG
    static func resetForTesting() {
        hovered = nil
        held = nil
    }
    #endif

    private static var hovered: (owner: Owner, kind: Kind)?
    private static var held: (owner: Owner, kind: Kind)?

    private static func apply() {
        #if os(macOS)
        CursorHelper.cursor(for: resolvedKind).set()
        #endif
    }
}

extension View {
    /// Names the cursor for as long as the pointer is over this view. Clears on teardown too — a
    /// view removed mid-hover (deselection, say) never gets a hover-exit.
    func cursorHover(_ kind: PlatformCursor.Kind, for owner: PlatformCursor.Owner) -> some View {
        onHover { PlatformCursor.hover($0 ? kind : nil, for: owner) }
            .onDisappear { PlatformCursor.clear(owner) }
    }
}

#if os(macOS)
import AppKit

enum CursorHelper {
    /// Memoized because `hold` re-sets the cursor on every tick of a drag, and `frameResize`
    /// builds one each call — a resize drag collapses to one construction plus N cheap `set()`s.
    static func cursor(for kind: PlatformCursor.Kind) -> NSCursor {
        if let memo, memo.kind == kind { return memo.cursor }
        let cursor = makeCursor(for: kind)
        memo = (kind, cursor)
        return cursor
    }

    private static var memo: (kind: PlatformCursor.Kind, cursor: NSCursor)?

    private static func makeCursor(for kind: PlatformCursor.Kind) -> NSCursor {
        switch kind {
        case .arrow: NSCursor.arrow
        case .openHand: NSCursor.openHand
        case .closedHand: NSCursor.closedHand
        case .rotate: rotateCursor
        case .resize(let edge, let rotation): resizeCursor(for: edge, rotation: rotation)
        }
    }

    /// Returns a resize cursor for the given edge, adjusted for the shape's rotation.
    static func resizeCursor(for edge: ResizeEdge, rotation: Double) -> NSCursor {
        let baseIndex: Int = switch edge {
        case .top: 0
        case .topRight: 1
        case .right: 2
        case .bottomRight: 3
        case .bottom: 4
        case .bottomLeft: 5
        case .left: 6
        case .topLeft: 7
        }

        let steps = Int((rotation / 45).rounded())
        let position: NSCursor.FrameResizePosition = switch ((baseIndex + steps) % 8 + 8) % 8 {
        case 0: .top
        case 1: .topRight
        case 2: .right
        case 3: .bottomRight
        case 4: .bottom
        case 5: .bottomLeft
        case 6: .left
        default: .topLeft
        }
        return NSCursor.frameResize(position: position, directions: .all)
    }

    /// A circular-arrow cursor for rotation.
    static let rotateCursor: NSCursor = {
        let size: CGFloat = 20
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            let center = CGPoint(x: size / 2, y: size / 2)
            let radius: CGFloat = 6.5
            // Arc spanning 270 degrees (leave a gap for the arrowhead)
            let startAngle: CGFloat = .pi / 4          // 45 degrees
            let endAngle: CGFloat = startAngle - 1.5 * .pi  // -270 degrees sweep

            // White outline for contrast
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(3.5)
            ctx.setLineCap(.round)
            ctx.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
            ctx.strokePath()

            // Black arc
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineWidth(1.5)
            ctx.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
            ctx.strokePath()

            // Arrowhead at the end of the arc
            let tipX = center.x + radius * cos(endAngle)
            let tipY = center.y + radius * sin(endAngle)
            // Tangent direction (perpendicular to radius, in direction of arc motion)
            let tangent = endAngle + .pi / 2
            let arrowLen: CGFloat = 5
            let spread: CGFloat = 0.5

            let p1 = CGPoint(x: tipX - arrowLen * cos(tangent - spread),
                             y: tipY - arrowLen * sin(tangent - spread))
            let p2 = CGPoint(x: tipX - arrowLen * cos(tangent + spread),
                             y: tipY - arrowLen * sin(tangent + spread))

            // White outline
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(3.5)
            ctx.move(to: p1); ctx.addLine(to: CGPoint(x: tipX, y: tipY))
            ctx.addLine(to: p2)
            ctx.strokePath()

            // Black arrowhead
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineWidth(1.5)
            ctx.move(to: p1); ctx.addLine(to: CGPoint(x: tipX, y: tipY))
            ctx.addLine(to: p2)
            ctx.strokePath()

            return true
        }

        return NSCursor(image: image, hotSpot: NSPoint(x: size / 2, y: size / 2))
    }()
}
#endif
