import SwiftUI

struct CoachStepAnchor {
    let attachmentAnchor: PopoverAttachmentAnchor
    let arrowEdge: Edge
}

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
            steps: [step: CoachStepAnchor(attachmentAnchor: attachmentAnchor, arrowEdge: arrowEdge)],
            state: state,
            isActive: isActive
        ))
    }

    /// Hosts several coach steps on one anchor view through a single popover
    /// modifier. iPadOS only honors the first popover modifier in a hosting
    /// context, so sibling steps inside the inspector must share one.
    func coachPopover(
        steps: [OnboardingCoachStep: CoachStepAnchor],
        state: AppState
    ) -> some View {
        modifier(CoachPopoverModifier(steps: steps, state: state, isActive: true))
    }

    /// Anchors a coach-mark popover on a plain background view sharing this
    /// view's geometry — iPadOS doesn't give a `Menu` usable popover-anchor
    /// geometry, so a directly attached popover presents detached from it.
    func coachPopoverAnchor(
        step: OnboardingCoachStep,
        state: AppState,
        arrowEdge: Edge = .top
    ) -> some View {
        background {
            Color.clear.coachPopover(step: step, state: state, arrowEdge: arrowEdge)
        }
    }
}

private struct CoachPopoverModifier: ViewModifier {
    let steps: [OnboardingCoachStep: CoachStepAnchor]
    @Bindable var state: AppState
    let isActive: Bool
    /// Keeps the card content rendering while the popover animates out —
    /// `activeStep` goes nil the instant the step clears, and a live-resolved
    /// `if let` would collapse the dismissing popover to an empty view.
    @State private var lastShownStep: OnboardingCoachStep?

    private var activeStep: OnboardingCoachStep? {
        guard isActive, let step = state.coachStep, steps[step] != nil else { return nil }
        return step
    }

    private var contentStep: OnboardingCoachStep? {
        activeStep ?? lastShownStep
    }

    private var isPresented: Binding<Bool> {
        Binding(
            get: { activeStep != nil },
            set: { newValue in
                // Dismissal driven by the system (click-outside, etc.) ends the tour.
                if !newValue, activeStep != nil {
                    state.endCoach()
                }
            }
        )
    }

    func body(content: Content) -> some View {
        let anchor = activeStep.flatMap { steps[$0] }
        content.popover(
            isPresented: isPresented,
            attachmentAnchor: anchor?.attachmentAnchor ?? .rect(.bounds),
            arrowEdge: anchor?.arrowEdge ?? .top
        ) {
            if let step = contentStep {
                CoachPopoverContent(step: step, state: state)
            }
        }
        .onChange(of: activeStep) { _, step in
            if let step { lastShownStep = step }
        }
    }
}

private struct CoachPopoverContent: View {
    let step: OnboardingCoachStep
    @Bindable var state: AppState
    @Environment(StoreService.self) private var store
    @State private var isCloseHovered = false

    private var isLastStep: Bool { step.next == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: UIMetrics.Coach.stackSpacing) {
            header
            title
            message
            if step == .pro {
                buyProButton
            }
            footer
        }
        .padding(UIMetrics.Coach.padding)
        .frame(width: UIMetrics.Coach.width)
    }

    private var buyProButton: some View {
        Button {
            state.endCoach()
            #if os(iOS)
            // Let the popover dismiss before the paywall sheet presents.
            Task { @MainActor in
                try? await Task.sleep(for: OnboardingCoachStep.presentationSettleDelay)
                store.presentPaywall(for: .general)
            }
            #else
            store.presentPaywall(for: .general)
            #endif
        } label: {
            Label("Buy Pro", systemImage: "crown")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        #if os(iOS)
        .controlSize(.large)
        #endif
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(step.accentColor.opacity(UIMetrics.Opacity.accentBadge))
                Image(systemName: step.icon)
                    .font(.system(size: UIMetrics.Coach.iconSize, weight: .semibold))
                    .foregroundStyle(step.accentColor)
            }
            .frame(width: UIMetrics.Coach.iconBadgeSize, height: UIMetrics.Coach.iconBadgeSize)

            progressDots

            Spacer(minLength: 0)

            Button {
                state.endCoach()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: UIMetrics.Coach.closeIconSize, weight: .bold))
                    .foregroundStyle(isCloseHovered ? Color.primary : .secondary)
                    .frame(width: UIMetrics.Coach.closeButtonSize, height: UIMetrics.Coach.closeButtonSize)
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
                    .frame(
                        width: isActive ? UIMetrics.Coach.dotActiveWidth : UIMetrics.Coach.dotHeight,
                        height: UIMetrics.Coach.dotHeight
                    )
            }
        }
        .animation(.easeOut(duration: 0.2), value: step)
    }

    private var title: some View {
        Text(step.title)
            .font(.system(size: UIMetrics.Coach.titleSize, weight: .semibold))
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
                .compactControlSize()
            }

            Spacer(minLength: 0)

            Text("\(step.stepNumber) of \(OnboardingCoachStep.totalSteps)")
                .font(.system(size: UIMetrics.FontSize.hint, design: .monospaced))
                .foregroundStyle(.tertiary)

            Spacer(minLength: 0)

            // On the Pro step the Buy Pro CTA is the single prominent button.
            if isLastStep {
                advanceButton.buttonStyle(.bordered)
            } else {
                advanceButton.buttonStyle(.borderedProminent)
            }
        }
    }

    private var advanceButton: some View {
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
        .compactControlSize()
    }
}
