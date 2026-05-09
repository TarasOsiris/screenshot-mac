import SwiftUI

extension View {
    /// Anchors a coach-mark popover for the given onboarding step. The popover
    /// is shown when `state.coachStep` matches `step` AND `isActive` is true.
    /// `isActive` lets callers gate which instance owns the anchor when a view
    /// is rendered multiple times (e.g. one per row). `attachmentAnchor` defaults
    /// to the source view's bounds; use `.point(.center)` to anchor at the
    /// middle of a large area like the canvas.
    func coachPopover(
        step: OnboardingCoachStep,
        state: AppState,
        isActive: Bool = true,
        arrowEdge: Edge = .top,
        attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds)
    ) -> some View {
        modifier(CoachPopoverModifier(
            step: step,
            state: state,
            isActive: isActive,
            arrowEdge: arrowEdge,
            attachmentAnchor: attachmentAnchor
        ))
    }
}

private struct CoachPopoverModifier: ViewModifier {
    let step: OnboardingCoachStep
    @Bindable var state: AppState
    let isActive: Bool
    let arrowEdge: Edge
    let attachmentAnchor: PopoverAttachmentAnchor

    private var isPresented: Binding<Bool> {
        Binding(
            get: { isActive && state.coachStep == step },
            set: { newValue in
                // Dismissal driven by the system (click-outside, etc.) ends the tour.
                if !newValue, isActive, state.coachStep == step {
                    state.endCoach()
                }
            }
        )
    }

    func body(content: Content) -> some View {
        content.popover(
            isPresented: isPresented,
            attachmentAnchor: attachmentAnchor,
            arrowEdge: arrowEdge
        ) {
            CoachPopoverContent(step: step, state: state)
        }
    }
}

private struct CoachPopoverContent: View {
    let step: OnboardingCoachStep
    @Bindable var state: AppState
    @State private var isCloseHovered = false

    private var isLastStep: Bool { step.next == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            title
            message
            footer
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 14))
        .frame(width: 300)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(step.accentColor.opacity(UIMetrics.Opacity.accentBadge))
                Image(systemName: step.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(step.accentColor)
            }
            .frame(width: 28, height: 28)

            progressDots

            Spacer(minLength: 0)

            Button {
                state.endCoach()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isCloseHovered ? Color.primary : .secondary)
                    .frame(width: 18, height: 18)
                    .background(
                        Circle().fill(Color.primary.opacity(isCloseHovered ? 0.1 : 0))
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Skip tour")
            .onHover { isCloseHovered = $0 }
        }
    }

    private var progressDots: some View {
        HStack(spacing: 5) {
            ForEach(OnboardingCoachStep.allCases) { other in
                let isActive = other == step
                let isPast = other.rawValue < step.rawValue
                Capsule()
                    .fill(isActive ? step.accentColor : Color.secondary.opacity(isPast ? 0.6 : 0.25))
                    .frame(width: isActive ? 16 : 6, height: 6)
            }
        }
        .animation(.easeOut(duration: 0.2), value: step)
    }

    private var title: some View {
        Text(step.title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var message: some View {
        Text(step.message)
            .font(.system(size: UIMetrics.FontSize.body))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .lineSpacing(2)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if step.previous != nil {
                Button {
                    state.goBackInCoach()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Spacer(minLength: 0)

            Text("\(step.stepNumber) of \(OnboardingCoachStep.totalSteps)")
                .font(.system(size: UIMetrics.FontSize.hint, design: .monospaced))
                .foregroundStyle(.tertiary)

            Spacer(minLength: 0)

            Button {
                state.advanceCoach()
            } label: {
                if isLastStep {
                    Text("Done")
                } else {
                    // Flip Label so the chevron sits after the title — Label has no
                    // built-in icon-trailing variant, and an HStack would lose the
                    // labelStyle integration the borderedProminent button relies on.
                    Label("Next", systemImage: "chevron.right")
                        .labelStyle(.titleAndIcon)
                        .environment(\.layoutDirection, .rightToLeft)
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }
}
