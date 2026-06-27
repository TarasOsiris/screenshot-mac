#if os(iOS)
import SwiftUI

// Illustrations for onboarding steps 2-4. Each showcases the step's feature with the app's real
// rendering components (device frames, the gradient renderer, real template previews) and animates
// only while its page is on screen (`isActive`) and motion is allowed. They mirror
// OnboardingTemplateMarquee's conventions. Animated subviews are built once (outside the
// TimelineView) so only transforms recompute per frame, not the device frames themselves.

private let onboardingDeviceGroupId = "iphone17promax"

// A small bundled home-screen capture shown inside every device frame across the onboarding
// illustrations. Decoded once.
private let onboardingDeviceScreen = NSImage(named: "OnboardingDeviceScreen")

// MARK: - Step 2 · Add your content

/// An empty real iPhone 17 Pro Max frame, surrounded by gently drifting "content" chips
/// (text, shape, photo, frame) — the things you drop onto the canvas.
struct OnboardingAddContentIllustration: View {
    let images: [NSImage]
    var accentColor: Color = .purple
    var reduceMotion = false
    var isActive = true

    private let gradient = GradientConfig(color1: .orange, color2: .pink, angle: 145, gradientType: .linear)

    var body: some View {
        GeometryReader { geo in
            let frame = DeviceFrameCatalog.preferredFrame(forGroupId: onboardingDeviceGroupId)
            let aspect = frame.map { $0.baseDimensions.width / $0.baseDimensions.height } ?? 0.49
            let phoneHeight = min(geo.size.height * 0.78, 280)
            let phoneWidth = phoneHeight * aspect

            ZStack {
                gradient.gradientFill

                DeviceFrameView(
                    category: .iphone, bodyColor: .black,
                    width: phoneWidth, height: phoneHeight,
                    screenshotImage: onboardingDeviceScreen,
                    deviceFrameId: frame?.id
                )
                .frame(width: phoneWidth, height: phoneHeight)
                .shadow(color: .black.opacity(0.18), radius: 14, y: 8)

                chips(in: geo.size)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(UIMetrics.Stroke.subtle, lineWidth: UIMetrics.BorderWidth.hairline)
            )
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func chips(in size: CGSize) -> some View {
        let x = min(size.width * 0.34, 150)
        let y = min(size.height * 0.30, 120)
        let slots: [CGSize] = [
            CGSize(width: -x, height: -y),
            CGSize(width: x, height: -y * 0.66),
            CGSize(width: -x * 0.9, height: y * 0.7),
            CGSize(width: x, height: y),
        ]
        let cards = chipViews()

        if reduceMotion || !isActive {
            chipStack(cards, slots) { _ in .zero }
        } else {
            TimelineView(.animation(paused: !isActive)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                chipStack(cards, slots) { i in
                    CGSize(width: 0, height: sin(t * 0.85 + Double(i) * 1.4) * 6)
                }
            }
        }
    }

    private func chipStack(_ cards: [AnyView], _ slots: [CGSize], drift: @escaping (Int) -> CGSize) -> some View {
        ZStack {
            ForEach(0..<cards.count, id: \.self) { i in
                cards[i].offset(slots[i] + drift(i))
            }
        }
    }

    private func chipViews() -> [AnyView] {
        [
            AnyView(chipCard {
                Text(verbatim: "Aa").font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(accentColor)
            }),
            AnyView(chipCard {
                StarShape(pointCount: 5).fill(accentColor).padding(11)
            }),
            AnyView(chipCard {
                Image(systemName: "photo").font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(accentColor)
            }),
            AnyView(chipCard {
                Image(systemName: "iphone").font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(accentColor)
            }),
        ]
    }

    @ViewBuilder
    private func chipCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(UIMetrics.Stroke.subtle, lineWidth: UIMetrics.BorderWidth.hairline)
            )
            .shadow(color: .black.opacity(0.1), radius: 7, y: 4)
    }
}

// MARK: - Step 3 · Style it

/// A clipped, staggered wall of iPhone 17 Pro Max frames on the real gradient renderer, with a
/// bigger interactive background switcher beneath: it auto-cycles until the user taps a swatch,
/// then stays on the chosen background.
struct OnboardingStyleIllustration: View {
    let images: [NSImage]
    var accentColor: Color = .orange
    var reduceMotion = false
    var isActive = true

    @State private var selection: Int?

    private let gradients: [GradientConfig] = [
        GradientConfig(color1: .orange, color2: .pink, angle: 135, gradientType: .linear),
        GradientConfig(color1: .blue, color2: .purple, angle: 160, gradientType: .linear),
        GradientConfig(color1: .teal, color2: .green, angle: 120, gradientType: .radial),
        GradientConfig(color1: .indigo, color2: .cyan, angle: 90, gradientType: .linear),
        GradientConfig(color1: .pink, color2: .yellow, angle: 210, gradientType: .linear),
    ]
    private let period: Double = 2.4

    private var autoCycles: Bool { selection == nil && !reduceMotion && isActive }

    var body: some View {
        GeometryReader { geo in
            panel(width: geo.size.width, height: geo.size.height)
                .overlay(alignment: .bottom) {
                    backgroundSwitcher()
                        .padding(.bottom, 14)
                }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity)
    }

    private func panel(width: CGFloat, height: CGFloat) -> some View {
        let frame = DeviceFrameCatalog.preferredFrame(forGroupId: onboardingDeviceGroupId)
        let aspect = frame.map { $0.baseDimensions.width / $0.baseDimensions.height } ?? 0.49
        let deviceH = min(height * 0.40, width * 0.44)
        let deviceW = deviceH * aspect

        return ZStack {
            gradientBackdrop(width: width, height: height)
            deviceGrid(width: width, height: height, frameId: frame?.id, deviceW: deviceW, deviceH: deviceH)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(UIMetrics.Stroke.subtle, lineWidth: UIMetrics.BorderWidth.hairline)
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func gradientBackdrop(width: CGFloat, height: CGFloat) -> some View {
        if let selection {
            gradients[selection].gradientFill.frame(width: width, height: height)
        } else if reduceMotion || !isActive {
            gradients[0].gradientFill.frame(width: width, height: height)
        } else {
            TimelineView(.animation(paused: !isActive)) { timeline in
                let p = phase(timeline.date)
                ZStack {
                    gradients[p.current].gradientFill
                    gradients[p.next].gradientFill.opacity(p.fade)
                }
                .frame(width: width, height: height)
            }
        }
    }

    /// A staggered grid (odd columns shifted down half a row) that overflows the panel so the
    /// rounded-rect clip crops it. Built once — kept outside the gradient's TimelineView so the
    /// device frames don't rebuild every animation tick.
    private func deviceGrid(width: CGFloat, height: CGFloat, frameId: String?,
                            deviceW: CGFloat, deviceH: CGFloat) -> some View {
        let gap: CGFloat = 22
        let colStep = deviceW + gap
        let rowStep = deviceH + gap
        let cols = Int(ceil(width / colStep)) + 2
        let rows = Int(ceil(height / rowStep)) + 2
        let gridW = CGFloat(cols - 1) * colStep
        let gridH = CGFloat(rows - 1) * rowStep

        return ZStack {
            ForEach(0..<cols, id: \.self) { c in
                ForEach(0..<rows, id: \.self) { r in
                    let shift = c.isMultiple(of: 2) ? 0 : rowStep / 2
                    let x = width / 2 - gridW / 2 + CGFloat(c) * colStep
                    let y = height / 2 - gridH / 2 + CGFloat(r) * rowStep + shift
                    DeviceFrameView(
                        category: .iphone, bodyColor: .black,
                        width: deviceW, height: deviceH,
                        screenshotImage: onboardingDeviceScreen,
                        deviceFrameId: frameId
                    )
                    .frame(width: deviceW, height: deviceH)
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
                    .position(x: x, y: y)
                }
            }
        }
        .frame(width: width, height: height)
    }

    @ViewBuilder
    private func backgroundSwitcher() -> some View {
        if autoCycles {
            TimelineView(.animation(paused: !isActive)) { timeline in
                swatchRow(active: phase(timeline.date).current)
            }
        } else {
            swatchRow(active: selection ?? 0)
        }
    }

    private func phase(_ date: Date) -> (current: Int, next: Int, fade: Double) {
        let cycle = date.timeIntervalSinceReferenceDate / period
        let i = Int(floor(cycle)) % gradients.count
        let next = (i + 1) % gradients.count
        let frac = cycle - floor(cycle)
        let fade = min(1, max(0, (frac - 0.75) / 0.25))
        return (i, next, fade)
    }

    private func swatchRow(active: Int) -> some View {
        HStack(spacing: 14) {
            ForEach(gradients.indices, id: \.self) { i in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selection = i }
                } label: {
                    Circle()
                        .fill(gradients[i].linearGradient)
                        .frame(width: 34, height: 34)
                        .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1.5))
                        .overlay(
                            Circle().strokeBorder(accentColor, lineWidth: 2.5)
                                .padding(-4)
                                .opacity(i == active ? 1 : 0)
                        )
                        .scaleEffect(i == active ? 1.12 : 1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Background \(i + 1)"))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .background(.ultraThinMaterial, in: Capsule())
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: active)
    }
}

// MARK: - Step 4 · Export

/// A fan of finished-looking screenshots — each a gradient background with a padded iPhone 17 Pro
/// Max frame and a headline, like a real template — with a copy of the front card repeatedly
/// lifting off to suggest exporting them all at once.
struct OnboardingExportIllustration: View {
    let images: [NSImage]
    var accentColor: Color = .green
    var reduceMotion = false
    var isActive = true

    private let cards: [(gradient: GradientConfig, headline: String)] = [
        (GradientConfig(color1: .green, color2: .teal, angle: 135), "Plan your day"),
        (GradientConfig(color1: .blue, color2: .indigo, angle: 150), "Track progress"),
        (GradientConfig(color1: .orange, color2: .pink, angle: 120), "Share instantly"),
    ]
    private let period: Double = 2.6

    var body: some View {
        GeometryReader { geo in
            let frame = DeviceFrameCatalog.preferredFrame(forGroupId: onboardingDeviceGroupId)
            let aspect = frame.map { $0.baseDimensions.width / $0.baseDimensions.height } ?? 0.49
            let cardH = min(geo.size.height * 0.66, 300)
            let cardW = cardH * 0.6
            let front = card(0, frameId: frame?.id, aspect: aspect, width: cardW, height: cardH, badge: "PNG")

            ZStack {
                card(1, frameId: frame?.id, aspect: aspect, width: cardW, height: cardH)
                    .rotationEffect(.degrees(-12)).offset(x: -cardW * 0.5, y: 16)
                card(2, frameId: frame?.id, aspect: aspect, width: cardW, height: cardH)
                    .rotationEffect(.degrees(12)).offset(x: cardW * 0.5, y: 16)
                front
                flyer(front: front, height: cardH)
            }
            .position(x: geo.size.width / 2, y: geo.size.height / 2 + cardH * 0.04)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func card(_ i: Int, frameId: String?, aspect: CGFloat,
                      width: CGFloat, height: CGFloat, badge: String? = nil) -> ExportCard {
        ExportCard(
            image: onboardingDeviceScreen,
            frameId: frameId, aspect: aspect,
            gradient: cards[i].gradient, headline: cards[i].headline,
            width: width, height: height,
            badge: badge, accentColor: accentColor
        )
    }

    @ViewBuilder
    private func flyer<V: View>(front: V, height: CGFloat) -> some View {
        if reduceMotion || !isActive {
            EmptyView()
        } else {
            TimelineView(.animation(paused: !isActive)) { timeline in
                let p = timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: period) / period
                let lift = smoothstep(p)
                let opacity = min(1, p / 0.12) * (1 - smoothstep(max(0, (p - 0.55) / 0.45)))

                front
                .offset(y: -lift * height * 0.5)
                .scaleEffect(1 - lift * 0.08)
                .opacity(opacity)
            }
        }
    }

    private func smoothstep(_ x: Double) -> Double {
        let t = min(1, max(0, x))
        return t * t * (3 - 2 * t)
    }
}

/// A single "finished screenshot" card: gradient background, headline, and a padded device frame
/// holding a placeholder image — the shape of a real App Store template.
private struct ExportCard: View {
    let image: NSImage?
    let frameId: String?
    let aspect: CGFloat
    let gradient: GradientConfig
    let headline: String
    let width: CGFloat
    let height: CGFloat
    var badge: String?
    var accentColor: Color

    var body: some View {
        let deviceH = height * 0.72
        let deviceW = deviceH * aspect

        ZStack(alignment: .bottomTrailing) {
            ZStack {
                gradient.gradientFill

                VStack(spacing: height * 0.04) {
                    Text(verbatim: headline)
                        .font(.system(size: max(11, height * 0.075), weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, width * 0.1)
                        .padding(.top, height * 0.08)

                    DeviceFrameView(
                        category: .iphone, bodyColor: .black,
                        width: deviceW, height: deviceH,
                        screenshotImage: image,
                        deviceFrameId: frameId
                    )
                    .frame(width: deviceW, height: deviceH)
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 5)
                }
                .frame(width: width, height: height, alignment: .top)
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(UIMetrics.Stroke.subtle, lineWidth: UIMetrics.BorderWidth.hairline)
            )
            .shadow(color: .black.opacity(0.12), radius: 9, y: 5)

            if let badge {
                Text(badge)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(accentColor, in: Capsule())
                    .padding(8)
            }
        }
    }
}

private extension CGSize {
    static func + (lhs: CGSize, rhs: CGSize) -> CGSize {
        CGSize(width: lhs.width + rhs.width, height: lhs.height + rhs.height)
    }
}
#endif
