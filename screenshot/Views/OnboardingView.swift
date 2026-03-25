import SwiftUI

struct OnboardingView: View {
    var persistCompletion = true
    var onComplete: (() -> Void)?

    @AppStorage("onboardingCompleted") private var onboardingCompleted = false

    var body: some View {
        ZStack {
            background

            content
                .padding(26)
        }
        .frame(width: 760, height: 600)
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color.blue.opacity(0.06),
                    Color.green.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color.orange.opacity(0.12),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 280
            )

            Canvas { context, size in
                let dotSpacing: CGFloat = 28
                let dotRadius: CGFloat = 1.2
                let cols = Int(size.width / dotSpacing) + 1
                let rows = Int(size.height / dotSpacing) + 1
                for row in 0..<rows {
                    for col in 0..<cols {
                        let x = CGFloat(col) * dotSpacing + dotSpacing / 2
                        let y = CGFloat(row) * dotSpacing + dotSpacing / 2
                        let rect = CGRect(x: x - dotRadius, y: y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
                        context.fill(Path(ellipseIn: rect), with: .color(.primary.opacity(0.06)))
                    }
                }
            }
        }
        .ignoresSafeArea()
    }

    private var content: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 28)
                .padding(.horizontal, 28)
                .padding(.bottom, 20)

            steps
                .padding(.horizontal, 28)

            Spacer(minLength: 18)

            footer
                .padding(.horizontal, 28)
                .padding(.top, 18)
                .padding(.bottom, 24)
        }
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.white.opacity(0.14))
                }
                .shadow(color: .black.opacity(0.08), radius: 24, y: 12)
        }
    }

    // MARK: - Header

    private var header: some View {
        Image("Logo")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(height: 30)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Steps

    private static let stepColumns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    private var steps: some View {
        LazyVGrid(columns: Self.stepColumns, spacing: 16) {
            ForEach(Array(Self.stepData.enumerated()), id: \.offset) { index, step in
                StepCardView(index: index, step: step)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        Button {
            if persistCompletion {
                onboardingCompleted = true
            }
            onComplete?()
        } label: {
            Text("Get Started")
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 24)
                .padding(.vertical, 2)
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Data

    private static let stepData: [StepInfo] = [
        StepInfo(
            title: "Pick a template",
            description: "Start from a ready-made layout or a blank project. Templates come pre-sized for each store.",
            icon: "square.grid.2x2",
            shortcut: nil,
            color: .blue
        ),
        StepInfo(
            title: "Add your content",
            description: "Drop in screenshots, add text and shapes, pick a device frame. Drag to arrange.",
            icon: "plus.rectangle.on.rectangle",
            shortcut: "Drop images onto canvas",
            color: .purple
        ),
        StepInfo(
            title: "Style it",
            description: "Set backgrounds, colors, and gradients. Use the inspector on the right and properties bar at the bottom.",
            icon: "paintbrush",
            shortcut: nil,
            color: .orange
        ),
        StepInfo(
            title: "Export",
            description: "Export all screenshots at once as PNG or JPEG, ready to upload to App Store Connect or Google Play.",
            icon: "square.and.arrow.up",
            shortcut: "\u{2318}E",
            color: .green
        ),
    ]
}

private struct StepInfo {
    let title: String
    let description: String
    let icon: String
    let shortcut: String?
    let color: Color
}

private struct StepCardView: View {
    let index: Int
    let step: StepInfo
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Step \(index + 1)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(step.color)

                    Text(step.title)
                        .font(.system(size: 16, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(step.color.opacity(isHovered ? 0.2 : 0.12))

                    Image(systemName: step.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(step.color)
                }
                .frame(width: 40, height: 40)
            }

            Text(step.description)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)

            Spacer(minLength: 0)

            if let shortcut = step.shortcut {
                Text(shortcut)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 154, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.92))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    step.color.opacity(isHovered ? 0.16 : 0.1),
                                    .clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .shadow(color: .black.opacity(isHovered ? 0.08 : 0.03), radius: isHovered ? 12 : 6, y: isHovered ? 6 : 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(step.color.opacity(isHovered ? 0.28 : 0.08), lineWidth: 1)
        }
        .scaleEffect(isHovered ? 1.015 : 1.0)
        .offset(y: isHovered ? -2 : 0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

#Preview {
    OnboardingView()
}
