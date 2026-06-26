#if os(iOS)
import SwiftUI

/// Decorative "wall of templates" for the onboarding's first step: rows of real template previews
/// auto-scrolling in alternating directions. Row count adapts to the available height (2, or 3 when
/// there's room). Purely illustrative — never intercepts the TabView's horizontal swipe.
struct OnboardingTemplateMarquee: View {
    let images: [NSImage]
    var reduceMotion = false
    /// Animation pauses when the page isn't on screen, so it costs nothing once the user swipes on.
    var isActive = true

    private let cardWidth: CGFloat = 148
    private let cardHeight: CGFloat = 80
    private let spacing: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: spacing) {
                ForEach(0..<rowCount(forHeight: geo.size.height), id: \.self) { r in
                    MarqueeRow(images: rotated(by: r),
                               reversed: !r.isMultiple(of: 2),
                               viewportWidth: geo.size.width,
                               cardWidth: cardWidth, cardHeight: cardHeight, spacing: spacing,
                               reduceMotion: reduceMotion, isActive: isActive)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.1),
                        .init(color: .black, location: 0.9),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
            )
        }
        // Hard-clip horizontally so offset strips can't bleed onto the adjacent TabView page;
        // vertical is left unclipped so card drop shadows survive.
        .clipShape(HorizontalClip())
        .allowsHitTesting(false)
    }

    private func rowCount(forHeight height: CGFloat) -> Int {
        guard !images.isEmpty else { return 0 }
        let fit = Int(height / (cardHeight + spacing))
        return max(2, min(3, fit))
    }

    /// Every row shows the full set (large loop width → seamless) rotated to a different start so the
    /// rows don't line up.
    private func rotated(by row: Int) -> [NSImage] {
        guard !images.isEmpty else { return [] }
        let shift = (images.count / 3 * row) % images.count
        guard shift != 0 else { return images }
        return Array(images[shift...] + images[..<shift])
    }
}

/// Clips the left/right edges to the view bounds while leaving top/bottom effectively unbounded.
private struct HorizontalClip: Shape {
    func path(in rect: CGRect) -> Path {
        Path(rect.insetBy(dx: 0, dy: -2000))
    }
}

private struct MarqueeRow: View {
    let images: [NSImage]
    let reversed: Bool
    let viewportWidth: CGFloat
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let spacing: CGFloat
    let reduceMotion: Bool
    let isActive: Bool

    /// Points per second — gentle drift.
    private let speed: Double = 26

    /// Width of one full pass of the image set; the offset is taken modulo this so the motion is
    /// continuous (no animation reset).
    private var loopWidth: CGFloat { (cardWidth + spacing) * CGFloat(images.count) }

    /// Enough copies that the strip always spans the viewport plus one loop — guarantees no gap even
    /// when there are only a couple of previews.
    private var copies: Int {
        guard loopWidth > 0 else { return 1 }
        return max(3, Int((viewportWidth + cardWidth) / loopWidth) + 2)
    }

    var body: some View {
        if images.isEmpty {
            Color.clear.frame(height: cardHeight)
        } else {
            // Built once per body pass; the TimelineView closure only re-applies the offset, not the
            // whole card strip.
            let strip = cardStrip
            Group {
                if reduceMotion {
                    strip
                } else {
                    TimelineView(.animation(paused: !isActive)) { timeline in
                        let phase = (timeline.date.timeIntervalSinceReferenceDate * speed)
                            .truncatingRemainder(dividingBy: Double(loopWidth))
                        let x = reversed ? CGFloat(phase) - loopWidth : -CGFloat(phase)
                        strip.offset(x: x)
                    }
                }
            }
            .frame(height: cardHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var cardStrip: some View {
        HStack(spacing: spacing) {
            ForEach(0..<(images.count * copies), id: \.self) { i in
                MarqueeCard(image: images[i % images.count], width: cardWidth, height: cardHeight)
            }
        }
    }
}

private struct MarqueeCard: View {
    let image: NSImage
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(UIMetrics.Stroke.subtle, lineWidth: UIMetrics.BorderWidth.hairline)
            )
            .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
    }
}
#endif
