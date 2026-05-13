import SwiftUI

struct PostPurchaseCelebrationView: View {
    let context: StoreService.PaywallContext
    let onDismiss: () -> Void

    @State private var heroAppeared = false
    @State private var contentAppeared = false
    @State private var confettiStartedAt: Date?
    @State private var confettiActive = false

    private static let confettiDuration: TimeInterval = 4.5
    private static let confettiPieceCount = 60
    private static let confettiColors: [Color] = [.pink, .orange, .yellow, .green, .blue, .purple]
    private static let confettiPieces: [ConfettiPiece] = (0..<confettiPieceCount).map { i in
        let seed = Double(i)
        let xBase = abs((sin(seed * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1.0))
        let speed = 80.0 + abs(sin(seed * 1.71)) * 90.0
        let delay = abs(sin(seed * 0.91)) * 1.6
        let rotationRate = 90.0 + seed * 11.0
        let isCircle = i % 3 == 0
        let color = confettiColors[i % confettiColors.count]
        return ConfettiPiece(
            seed: seed,
            xBase: xBase,
            speed: speed,
            delay: delay,
            rotationRate: rotationRate,
            isCircle: isCircle,
            color: color
        )
    }

    var body: some View {
        ZStack {
            background
            confettiLayer
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                hero
                    .padding(.top, 36)
                    .padding(.horizontal, 32)

                divider
                    .padding(.horizontal, 32)
                    .padding(.top, 28)

                included
                    .padding(.horizontal, 32)
                    .padding(.top, 22)

                goal
                    .padding(.horizontal, 32)
                    .padding(.top, 22)

                Spacer(minLength: 18)

                footer
                    .padding(.horizontal, 32)
                    .padding(.bottom, 28)
            }
        }
        .frame(width: 540, height: 620)
        .onAppear {
            confettiStartedAt = Date()
            confettiActive = true
            withAnimation(.spring(response: 0.55, dampingFraction: 0.62).delay(0.05)) {
                heroAppeared = true
            }
            withAnimation(.easeOut(duration: 0.45).delay(0.25)) {
                contentAppeared = true
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(Self.confettiDuration))
            confettiActive = false
        }
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color.purple.opacity(0.08),
                    Color.orange.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [Color.yellow.opacity(0.18), .clear],
                center: .top,
                startRadius: 10,
                endRadius: 320
            )
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var confettiLayer: some View {
        if confettiActive, let confettiStartedAt {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { timeline in
                let elapsed = timeline.date.timeIntervalSince(confettiStartedAt)
                Canvas { context, size in
                    drawConfetti(in: context, size: size, elapsed: elapsed)
                }
            }
            .transition(.opacity)
        }
    }

    private func drawConfetti(in context: GraphicsContext, size: CGSize, elapsed: TimeInterval) {
        guard elapsed < Self.confettiDuration else { return }
        let opacity = max(0, 1.0 - elapsed / Self.confettiDuration)
        for piece in Self.confettiPieces {
            let xJitter = (cos(piece.seed * 7.233 + elapsed * 0.6) + 1.0) * 6.0
            let x = piece.xBase * size.width + xJitter
            let t = max(0, elapsed - piece.delay)
            let y = -20.0 + t * piece.speed
            guard y < size.height + 20 else { continue }
            let rotation = t * piece.rotationRate * .pi / 180.0

            var transform = CGAffineTransform.identity
                .translatedBy(x: x, y: y)
                .rotated(by: rotation)

            let rect = CGRect(x: -4, y: -3, width: 8, height: 6)
            let path: Path = piece.isCircle ? Path(ellipseIn: rect) : Path(rect)

            var ctx = context
            ctx.transform = transform
            ctx.opacity = opacity
            ctx.fill(path, with: .color(piece.color))
        }
    }

    private var hero: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.yellow, .orange, .pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 84, height: 84)
                    .shadow(color: .orange.opacity(0.35), radius: 18, y: 8)

                Image(systemName: "crown.fill")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
            }
            .scaleEffect(heroAppeared ? 1.0 : 0.4)
            .rotationEffect(.degrees(heroAppeared ? 0 : -25))
            .opacity(heroAppeared ? 1 : 0)

            VStack(spacing: 6) {
                Text("You’re Pro!")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Your purchase is complete — Screenshot Bro Pro is unlocked on this Apple Account.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .opacity(contentAppeared ? 1 : 0)
            .offset(y: contentAppeared ? 0 : 8)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(UIMetrics.Opacity.hairlineOverlay))
            .frame(height: 1)
            .opacity(contentAppeared ? 1 : 0)
    }

    private var included: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What’s included")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(spacing: 8) {
                featureRow(icon: "square.stack.3d.up.fill", color: .blue, text: "Unlimited projects")
                featureRow(icon: "rectangle.grid.1x2.fill", color: .purple, text: "Unlimited rows per project")
                featureRow(icon: "photo.on.rectangle.angled", color: .pink, text: "Unlimited screenshots per row")
            }
        }
        .opacity(contentAppeared ? 1 : 0)
        .offset(y: contentAppeared ? 0 : 8)
    }

    private func featureRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.section, style: .continuous)
                    .fill(color.opacity(UIMetrics.Opacity.accentBadge))
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
            }
            .frame(width: 28, height: 28)

            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.green)
        }
    }

    private var goal: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 28, height: 28)
                .background(
                    Color.orange.opacity(UIMetrics.Opacity.accentBadge),
                    in: RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.section, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("Ship screenshots that convert")
                    .font(.system(size: 13, weight: .semibold))
                Text("Build a polished store listing across every language and device — no caps, no compromises.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.section, style: .continuous)
                .fill(Color.primary.opacity(UIMetrics.Opacity.sectionFill))
                .overlay {
                    RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.section, style: .continuous)
                        .strokeBorder(.separator.opacity(UIMetrics.Opacity.sectionBorder), lineWidth: UIMetrics.BorderWidth.hairline)
                }
        }
        .opacity(contentAppeared ? 1 : 0)
        .offset(y: contentAppeared ? 0 : 8)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button(action: onDismiss) {
                Text(primaryActionTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

            Text(nextStepHint)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .opacity(contentAppeared ? 1 : 0)
    }

    private var primaryActionTitle: String {
        switch context {
        case .projectLimit:
            return String(localized: "Create Your Next Project")
        case .rowLimit:
            return String(localized: "Add Your Next Row")
        case .templateLimit:
            return String(localized: "Add Your Next Screenshot")
        case .general:
            return String(localized: "Start Creating")
        }
    }

    private var nextStepHint: String {
        switch context {
        case .projectLimit:
            return String(localized: "Pick up right where you left off — your project list is now unlimited.")
        case .rowLimit:
            return String(localized: "Pick up right where you left off — add as many rows as you need.")
        case .templateLimit:
            return String(localized: "Pick up right where you left off — add as many screenshots per row as you need.")
        case .general:
            return String(localized: "Tip: drop a screenshot onto any canvas to get started.")
        }
    }
}

private struct ConfettiPiece {
    let seed: Double
    let xBase: Double
    let speed: Double
    let delay: Double
    let rotationRate: Double
    let isCircle: Bool
    let color: Color
}

#Preview("General") {
    PostPurchaseCelebrationView(context: .general, onDismiss: {})
}

#Preview("Row limit") {
    PostPurchaseCelebrationView(context: .rowLimit, onDismiss: {})
}
