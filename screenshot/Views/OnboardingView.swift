import SwiftUI

struct OnboardingView: View {
    var persistCompletion = true
    var onComplete: (() -> Void)?

    @AppStorage("onboardingCompleted") private var onboardingCompleted = false
    @State private var hoveredStep: Int?

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                header
                    .padding(.top, 40)
                    .padding(.bottom, 28)

                steps
                    .padding(.horizontal, 48)

                Spacer(minLength: 20)

                footer
                    .padding(.bottom, 32)
            }
        }
        .frame(width: 640, height: 520)
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

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

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            Image("Logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 28)

            VStack(spacing: 6) {
                Text("Welcome to Screenshot Bro")
                    .font(.system(size: 22, weight: .bold, design: .rounded))

                Text("Create App Store screenshots in minutes")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Steps

    private var steps: some View {
        HStack(spacing: 14) {
            ForEach(Array(stepData.enumerated()), id: \.offset) { index, step in
                stepCard(index: index, step: step)
            }
        }
    }

    private func stepCard(index: Int, step: StepInfo) -> some View {
        let isHovered = hoveredStep == index
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("\(index + 1)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(step.color.gradient, in: Circle())

                Image(systemName: step.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(step.color)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(step.title)
                    .font(.system(size: 14, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)

                Text(step.description)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(1)
            }

            Spacer(minLength: 0)

            if !step.shortcut.isEmpty {
                Text(step.shortcut)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(isHovered ? 0.08 : 0.03), radius: isHovered ? 8 : 4, y: isHovered ? 3 : 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(step.color.opacity(isHovered ? 0.3 : 0.0), lineWidth: 1)
        }
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            hoveredStep = hovering ? index : nil
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 16) {
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
        }
    }

    // MARK: - Data

    private var stepData: [StepInfo] {
        [
            StepInfo(
                title: "Pick a template",
                description: "Start from a ready-made layout or a blank project. Templates come pre-sized for each store.",
                icon: "square.grid.2x2",
                shortcut: "",
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
                shortcut: "",
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
}

private struct StepInfo {
    let title: String
    let description: String
    let icon: String
    let shortcut: String
    let color: Color
}

#Preview {
    OnboardingView()
}
