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
            let phoneHeight = min(geo.size.height * 0.88, 320)
            let phoneWidth = phoneHeight * aspect

            ZStack {
                gradient.gradientFill

                backgroundAccents(in: geo.size)

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

    /// Faint white text/vector accents scattered to the sides of the device so the canvas reads as a
    /// styled work surface. Static and low-opacity — the foreground chips carry the motion.
    private func backgroundAccents(in size: CGSize) -> some View {
        let w = size.width, h = size.height
        return ZStack {
            StarShape(pointCount: 5).fill(.white).frame(width: w * 0.13, height: w * 0.13)
                .offset(x: -0.36 * w, y: -0.32 * h)
            accentSymbol("sparkles", w * 0.13).offset(x: 0.37 * w, y: -0.28 * h)
            Text(verbatim: "Aa").font(.system(size: w * 0.11, weight: .heavy, design: .rounded))
                .foregroundStyle(.white).offset(x: -0.41 * w, y: 0.04 * h)
            accentSymbol("paintbrush.fill", w * 0.12).offset(x: 0.41 * w, y: 0.10 * h)
            Circle().strokeBorder(.white, lineWidth: max(3, w * 0.012)).frame(width: w * 0.12, height: w * 0.12)
                .offset(x: -0.30 * w, y: 0.36 * h)
            StarShape(pointCount: 6).fill(.white).frame(width: w * 0.11, height: w * 0.11)
                .offset(x: 0.33 * w, y: 0.36 * h)
        }
        .opacity(0.22)
    }

    private func accentSymbol(_ name: String, _ side: CGFloat) -> some View {
        Image(systemName: name)
            .font(.system(size: side, weight: .semibold))
            .foregroundStyle(.white)
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
                    .foregroundStyle(.white)
            }),
            AnyView(chipCard {
                StarShape(pointCount: 5).fill(.white).padding(11)
            }),
            AnyView(chipCard {
                Image(systemName: "photo").font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }),
            AnyView(chipCard {
                Image(systemName: "iphone").font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
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
        let preferred = DeviceFrameCatalog.preferredFrame(forGroupId: onboardingDeviceGroupId)
        let colorFrameIds = DeviceFrameCatalog.portraitColorFrameIds(forGroupId: onboardingDeviceGroupId)
        let frameIds = colorFrameIds.isEmpty ? [preferred?.id].compactMap { $0 } : colorFrameIds
        let aspect = preferred.map { $0.baseDimensions.width / $0.baseDimensions.height } ?? 0.49
        let deviceH = min(height * 0.46, width * 0.50)
        let deviceW = deviceH * aspect

        return ZStack {
            gradientBackdrop(width: width, height: height)
            scrollingWall(width: width, height: height, frameIds: frameIds, deviceW: deviceW, deviceH: deviceH)
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

    /// Points per second the wall drifts up-and-to-the-left — gentle and endless.
    private let wallScrollSpeed: Double = 13

    /// A staggered wall of randomly-colored iPhone frames that overflows the panel so the rounded-rect
    /// clip crops it. It scrolls diagonally, wrapping by the pattern's period (two columns horizontally,
    /// one row vertically) so the drift stays seamless. The wall is built once (the `wall` value) — only
    /// the offset recomputes per tick, so the device frames don't rebuild every frame.
    private func scrollingWall(width: CGFloat, height: CGFloat, frameIds: [String],
                               deviceW: CGFloat, deviceH: CGFloat) -> some View {
        let gap: CGFloat = 26
        let colStep = deviceW + gap
        let rowStep = deviceH + gap
        let xPeriod = colStep * 2
        // Extra cells on every side so the modulo wrap never exposes a gap as the wall drifts.
        let cols = Int(ceil(width / colStep)) + 4
        let rows = Int(ceil(height / rowStep)) + 4
        let gridW = CGFloat(cols - 1) * colStep
        let gridH = CGFloat(rows - 1) * rowStep

        let wall = ZStack {
            ForEach(0..<cols, id: \.self) { c in
                ForEach(0..<rows, id: \.self) { r in
                    let shift = c.isMultiple(of: 2) ? 0 : rowStep / 2
                    let x = width / 2 - gridW / 2 + CGFloat(c) * colStep
                    let y = height / 2 - gridH / 2 + CGFloat(r) * rowStep + shift
                    let seed = abs((c &* 49_297) &+ (r &* 12_911)) % 997
                    DeviceFrameView(
                        category: .iphone, bodyColor: .black,
                        width: deviceW, height: deviceH,
                        screenshotImage: onboardingDeviceScreen,
                        deviceFrameId: frameIds.isEmpty ? nil : frameIds[seed % frameIds.count]
                    )
                    .frame(width: deviceW, height: deviceH)
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
                    .position(x: x, y: y)
                }
            }
        }
        .frame(width: width, height: height)

        return Group {
            if reduceMotion || !isActive {
                wall
            } else {
                TimelineView(.animation(paused: !isActive)) { timeline in
                    let d = timeline.date.timeIntervalSinceReferenceDate * wallScrollSpeed
                    let dx = d.truncatingRemainder(dividingBy: Double(xPeriod))
                    let dy = d.truncatingRemainder(dividingBy: Double(rowStep))
                    wall.offset(x: -CGFloat(dx), y: -CGFloat(dy))
                }
            }
        }
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

/// A fan of three finished-looking screenshots — each a gradient background with a padded iPhone 17
/// Pro Max frame and a single punchy headline, like a real template.
struct OnboardingExportIllustration: View {
    let images: [NSImage]
    var reduceMotion = false
    var isActive = true

    private let cards: [(gradient: GradientConfig, headline: String)] = [
        (GradientConfig(color1: .green, color2: .teal, angle: 135), "Bold"),
        (GradientConfig(color1: .blue, color2: .indigo, angle: 150), "Crisp"),
        (GradientConfig(color1: .orange, color2: .pink, angle: 120), "Shine"),
    ]

    /// Seconds for one full open→close→open accordion cycle.
    private let accordionPeriod: Double = 5

    var body: some View {
        GeometryReader { geo in
            let frame = DeviceFrameCatalog.preferredFrame(forGroupId: onboardingDeviceGroupId)
            let aspect = frame.map { $0.baseDimensions.width / $0.baseDimensions.height } ?? 0.49
            let cardH = min(geo.size.height * 0.8, 360)
            let cardW = cardH * 0.6
            // Built once — the accordion only animates each card's rotation/offset, never its content.
            let leftCard = card(1, frameId: frame?.id, aspect: aspect, width: cardW, height: cardH)
            let rightCard = card(2, frameId: frame?.id, aspect: aspect, width: cardW, height: cardH)
            let frontCard = card(0, frameId: frame?.id, aspect: aspect, width: cardW, height: cardH)

            Group {
                if reduceMotion || !isActive {
                    fan(open: 1, cardW: cardW, left: leftCard, right: rightCard, front: frontCard)
                } else {
                    TimelineView(.animation(paused: !isActive)) { timeline in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        let open = 0.5 - 0.5 * cos(t * (2 * .pi / accordionPeriod))
                        fan(open: open, cardW: cardW, left: leftCard, right: rightCard, front: frontCard)
                    }
                }
            }
            .position(x: geo.size.width / 2, y: geo.size.height / 2 - cardH * 0.08)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The three-card fan at a given openness (0 = stacked tight, 1 = spread wide). The side cards
    /// rotate out and slide apart together, breathing like an accordion.
    private func fan(open: Double, cardW: CGFloat,
                     left: ExportCard, right: ExportCard, front: ExportCard) -> some View {
        let o = CGFloat(open)
        let angle = 4 + 13 * o
        let dx = cardW * (0.26 + 0.30 * o)
        return ZStack {
            left.rotationEffect(.degrees(-angle)).offset(x: -dx, y: 16)
            right.rotationEffect(.degrees(angle)).offset(x: dx, y: 16)
            front
        }
    }

    private func card(_ i: Int, frameId: String?, aspect: CGFloat,
                      width: CGFloat, height: CGFloat) -> ExportCard {
        ExportCard(
            image: onboardingDeviceScreen,
            frameId: frameId, aspect: aspect,
            gradient: cards[i].gradient, headline: cards[i].headline,
            width: width, height: height
        )
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

    var body: some View {
        let deviceH = height * 0.72
        let deviceW = deviceH * aspect

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
    }
}

private extension CGSize {
    static func + (lhs: CGSize, rhs: CGSize) -> CGSize {
        CGSize(width: lhs.width + rhs.width, height: lhs.height + rhs.height)
    }
}
#endif
