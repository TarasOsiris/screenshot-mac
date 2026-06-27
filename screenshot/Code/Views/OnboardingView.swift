import SwiftUI

struct OnboardingView: View {
    var persistCompletion = true
    var onComplete: (() -> Void)?

    @AppStorage(OnboardingPersistence.completedKey) private var onboardingCompleted = false
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(StoreService.self) private var store
    @State private var pageIndex = 0
    @State private var templatePreviews: [NSImage] = []
    #endif

    var body: some View {
        #if os(iOS)
        iOSContent
        #else
        macOSContent
        #endif
    }

    #if os(macOS)
    private var macOSContent: some View {
        ZStack {
            background

            content
                .padding(26)
        }
        .frame(width: 760, height: 600)
    }
    #endif

    #if os(iOS)
    // Index of the trailing Pro/paywall page (after the workflow step pages).
    private var proPageIndex: Int { Self.stepData.count }

    private var iOSContent: some View {
        ZStack {
            Color.platformWindowBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $pageIndex) {
                    ForEach(Array(Self.stepData.enumerated()), id: \.offset) { index, step in
                        Group {
                            if index == 0 {
                                iOSTemplatesPage(index: index, step: step)
                            } else {
                                iOSWorkflowPage(index: index, step: step)
                            }
                        }
                        .tag(index)
                    }

                    iOSProPage
                        .tag(proPageIndex)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: pageIndex)

                iOSControlBar
            }
        }
        .task {
            // Decoding the bundled previews is off the main actor so the cover never hitches on
            // first launch (onboarding is the first/only caller, so the template cache isn't contended).
            if templatePreviews.isEmpty {
                templatePreviews = await Task.detached(priority: .userInitiated) {
                    Array(TemplateService.availableTemplates().compactMap(\.previewImage).prefix(16))
                }.value
            }
        }
        .sheet(isPresented: Binding(
            get: { store.showPaywall },
            set: { if !$0 { store.dismissPaywall() } }
        )) {
            PaywallSheetContent(store: store)
        }
    }

    // MARK: - iOS control bar

    // Every page shares one fixed-height action bar so paging only animates the centered
    // illustration — the dots and buttons never move (no jump when reaching the Pro page).
    private var iOSControlBar: some View {
        VStack(spacing: 16) {
            iOSPageDots

            VStack(spacing: 10) {
                Button(action: primaryAction) {
                    Text(primaryActionTitle)
                        .font(.headline)
                        .contentTransition(.opacity)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(action: secondaryAction) {
                    // verbatim placeholder keeps the row's height without extracting a " " string.
                    Group {
                        if let secondaryActionTitle {
                            Text(secondaryActionTitle)
                        } else {
                            Text(verbatim: " ")
                        }
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                }
                .buttonStyle(.plain)
                .opacity(secondaryActionTitle == nil ? 0 : 1)
                .disabled(secondaryActionTitle == nil)
            }
            .frame(maxWidth: 360)
            .animation(.easeInOut, value: pageIndex)
            .animation(.easeInOut, value: store.isProUnlocked)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
    }

    private var primaryActionTitle: LocalizedStringKey {
        if pageIndex < proPageIndex { return "Continue" }
        return store.isProUnlocked ? "Start Creating" : "Unlock Pro"
    }

    private func primaryAction() {
        if pageIndex < proPageIndex {
            withAnimation { pageIndex += 1 }
        } else if store.isProUnlocked {
            complete()
        } else {
            store.presentPaywall(for: .general)
        }
    }

    private var secondaryActionTitle: LocalizedStringKey? {
        if pageIndex < proPageIndex { return "Skip" }
        return store.isProUnlocked ? nil : "Continue with Free"
    }

    private func secondaryAction() {
        if pageIndex < proPageIndex {
            withAnimation { pageIndex = proPageIndex }
        } else {
            complete()
        }
    }

    private var iOSPageDots: some View {
        HStack(spacing: 8) {
            ForEach(0...proPageIndex, id: \.self) { i in
                Circle()
                    .fill(i == pageIndex ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
        }
        .animation(.easeInOut, value: pageIndex)
    }

    // MARK: - iOS pages

    private func iOSPageHeader(index: Int, step: StepInfo) -> some View {
        VStack(spacing: 12) {
            Text("Step \(index + 1)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(step.color)
                .textCase(.uppercase)

            Text(step.title)
                .font(.title.weight(.bold))
                .multilineTextAlignment(.center)

            Text(step.iosDescription ?? step.description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func iOSStepIcon(step: StepInfo, side: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(step.color.opacity(0.14))

            Image(systemName: step.icon)
                .font(.system(size: side < 100 ? 40 : 52, weight: .semibold))
                .foregroundStyle(step.color)
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    // The "Pick a template" step leads with the text, then a live marquee of real template
    // previews. Until they load (or if none decode) it falls back to the standard step icon.
    @ViewBuilder
    private func iOSTemplatesPage(index: Int, step: StepInfo) -> some View {
        VStack(spacing: 20) {
            iOSPageHeader(index: index, step: step)
                .padding(.horizontal, 40)
                .padding(.top, 24)

            // Fills the remaining height; the marquee adapts its row count to fit, so the title
            // above can never be pushed off-screen.
            if templatePreviews.isEmpty {
                iOSStepIcon(step: step, side: horizontalSizeClass == .compact ? 88 : 112)
                    .frame(maxHeight: .infinity)
            } else {
                OnboardingTemplateMarquee(images: templatePreviews,
                                          reduceMotion: reduceMotion,
                                          isActive: pageIndex == index)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.4), value: templatePreviews.isEmpty)
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func iOSWorkflowPage(index: Int, step: StepInfo) -> some View {
        // Header pinned to the top exactly like the templates page, so the title/description
        // never shift position between steps; the illustration fills (and centers within) the rest.
        VStack(spacing: 20) {
            iOSPageHeader(index: index, step: step)
                .padding(.horizontal, 40)
                .padding(.top, 24)

            iOSStepIllustration(index: index, step: step)
                .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func iOSStepIllustration(index: Int, step: StepInfo) -> some View {
        let active = pageIndex == index
        switch step.illustration {
        case .addContent:
            OnboardingAddContentIllustration(images: templatePreviews, accentColor: step.color,
                                             reduceMotion: reduceMotion, isActive: active)
        case .style:
            OnboardingStyleIllustration(images: templatePreviews, accentColor: step.color,
                                        reduceMotion: reduceMotion, isActive: active)
        case .export:
            // Only Export needs real previews; the others degrade gracefully without them.
            if templatePreviews.isEmpty {
                iOSStepIcon(step: step, side: horizontalSizeClass == .compact ? 88 : 112)
            } else {
                OnboardingExportIllustration(images: templatePreviews, accentColor: step.color,
                                             reduceMotion: reduceMotion, isActive: active)
            }
        case .none:
            iOSStepIcon(step: step, side: horizontalSizeClass == .compact ? 88 : 112)
        }
    }

    private var iOSProPage: some View {
        let compact = horizontalSizeClass == .compact

        return VStack(spacing: compact ? 18 : 24) {
            if templatePreviews.isEmpty {
                Spacer()
            } else {
                OnboardingTemplateMarquee(images: templatePreviews,
                                          reduceMotion: reduceMotion,
                                          isActive: pageIndex == proPageIndex)
                    .frame(maxHeight: .infinity)
            }

            VStack(spacing: compact ? 20 : 28) {
                if store.isProUnlocked {
                    proSuccessContent
                } else {
                    proPitchContent
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var proPitchContent: some View {
        ZStack {
            Circle().fill(Color.accentColor.opacity(0.14))

            Image(systemName: "lock.open.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        }
        .frame(width: 100, height: 100)
        .accessibilityHidden(true)

        VStack(spacing: 12) {
            Text("Unlock Screenshot Bro Pro")
                .font(.title.weight(.bold))
                .multilineTextAlignment(.center)

            Text("Go unlimited and create as many screenshots as your apps need.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }

        VStack(alignment: .leading, spacing: 12) {
            proFeatureBullet("Unlimited projects")
            proFeatureBullet("Unlimited rows per project")
            proFeatureBullet("Unlimited screenshots per row")
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var proSuccessContent: some View {
        ZStack {
            Circle().fill(Color.green.opacity(0.14))

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.green)
        }
        .frame(width: 100, height: 100)
        .accessibilityHidden(true)

        VStack(spacing: 12) {
            Text("You’re Pro!")
                .font(.title.weight(.bold))

            Text("Everything is unlocked. Enjoy unlimited projects, rows, and screenshots.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func proFeatureBullet(_ text: LocalizedStringKey) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(text)
            Spacer(minLength: 0)
        }
        .font(.body)
    }
    #endif

    // MARK: - Background

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.platformWindowBackground,
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

    private var stepColumns: [GridItem] {
        #if os(iOS)
        // Two narrow columns wrap step titles mid-word on an iPhone; use one column there.
        if horizontalSizeClass == .compact {
            return [GridItem(.flexible())]
        }
        #endif
        return [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16)
        ]
    }

    private var steps: some View {
        LazyVGrid(columns: stepColumns, spacing: 16) {
            ForEach(Array(Self.stepData.enumerated()), id: \.offset) { index, step in
                StepCardView(index: index, step: step)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        Button {
            complete()
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

    private func complete() {
        if persistCompletion {
            onboardingCompleted = true
        }
        #if os(iOS)
        // A purchase made inside onboarding already showed its own success state, so drop any
        // celebration the store queued — otherwise it would surface on the next root paywall.
        store.cancelPendingCelebration()
        #endif
        onComplete?()
    }

    // MARK: - Data

    private static let stepData: [StepInfo] = [
        StepInfo(
            title: "Pick a template",
            description: "Start from a ready-made layout or a blank project. Templates come pre-sized for each store.",
            icon: "square.grid.2x2",
            color: .blue
        ),
        StepInfo(
            title: "Add your content",
            description: "Drop in screenshots, add text and shapes, pick a device frame. Drag to arrange.",
            icon: "plus.rectangle.on.rectangle",
            hint: "Drop images onto canvas",
            iosDescription: "Add screenshots from Photos or Files, then drop in text, shapes, and a device frame.",
            illustration: .addContent,
            color: .purple
        ),
        StepInfo(
            title: "Style it",
            description: "Set backgrounds, colors, and gradients. Use the inspector on the right and properties bar at the bottom.",
            icon: "paintbrush",
            iosDescription: "Set backgrounds, colors, and gradients, and fine-tune every element to match your brand.",
            illustration: .style,
            color: .orange
        ),
        StepInfo(
            title: "Export",
            description: "Export all screenshots at once as PNG or JPEG, ready to upload to App Store Connect or Google Play.",
            icon: "square.and.arrow.up",
            shortcutGlyph: "\u{2318}E",
            illustration: .export,
            color: .green
        ),
    ]
}

/// The iOS-only animated illustration a step shows in place of its static icon. Keyed off the
/// step's data rather than its array index so reordering steps can't mismatch the illustration.
private enum StepIllustration {
    case addContent, style, export
}

private struct StepInfo {
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    let icon: String
    var hint: LocalizedStringKey? = nil
    var shortcutGlyph: String? = nil
    // Used by the iPad/iOS flow when the desktop copy references mouse/keyboard or chrome
    // (drag-drop, the right inspector, ⌘E) that doesn't exist there.
    var iosDescription: LocalizedStringKey? = nil
    var illustration: StepIllustration? = nil
    let color: Color
}

private struct StepCardView: View {
    let index: Int
    let step: StepInfo
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
                        .fill(step.color.opacity(0.12))

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

            if let hint = step.hint {
                shortcutBadge { Text(hint) }
            } else if let glyph = step.shortcutGlyph {
                shortcutBadge { Text(verbatim: glyph) }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 154, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.platformControlBackground.opacity(0.92))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    step.color.opacity(0.1),
                                    .clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .shadow(color: .black.opacity(0.03), radius: 6, y: 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(step.color.opacity(0.08), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func shortcutBadge<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

#Preview {
    #if os(iOS)
    // iOS body reads StoreService from the environment — inject one so the preview doesn't trap.
    OnboardingView()
        .environment(StoreService())
    #else
    OnboardingView()
    #endif
}
