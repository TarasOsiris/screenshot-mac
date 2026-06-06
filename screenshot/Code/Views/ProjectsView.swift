#if os(iOS)
import SwiftUI

/// iPad root: a tab bar with Projects (a home screen listing every project) and Settings.
/// Each tab owns its own NavigationStack (the supported pattern: a TabView placed *inside* a
/// NavigationStack does not forward its tab content's title/toolbar to the outer bar, which
/// silently dropped the Projects title + New Project button). Opening a project pushes the
/// editor onto the Projects stack and hides the tab bar for the duration; the back button
/// returns here.
struct iPadRootView: View {
    @Environment(AppState.self) private var state
    @Environment(StoreService.self) private var store
    @Environment(AppNavigationRouter.self) private var router
    @AppStorage(OnboardingPersistence.completedKey) private var onboardingCompleted = false
    @State private var openedProjectId: UUID?

    var body: some View {
        @Bindable var router = router

        tabView(
            selectedTab: $router.selectedTab,
            settingsPath: $router.settingsPath
        )
        // If the active project changes underneath an open editor (e.g. an iCloud reload
        // dropped or replaced it), pop back to Projects instead of silently showing a
        // different project than the one the user opened.
        .onChange(of: state.activeProjectId) { _, newId in
            if let opened = openedProjectId, newId != opened {
                openedProjectId = nil
            }
        }
        // Paywall/celebration are presented from the root so they work on the Projects home
        // screen (e.g. tapping New Project at the free-tier limit) as well as the editor.
        // Suppressed while the onboarding cover is up (onboardingCompleted == false): onboarding
        // presents its own paywall on the same store state, and two sheets bound to one boolean
        // would conflict / leak a stray celebration once the cover dismisses.
        .sheet(isPresented: Binding(get: { store.showPaywall && onboardingCompleted }, set: { _ in store.dismissPaywall() }),
               onDismiss: { store.presentPendingCelebrationIfNeeded() }) {
            PaywallSheetContent(store: store)
        }
        .sheet(isPresented: Binding(get: { store.purchaseCelebrationContext != nil && onboardingCompleted }, set: { if !$0 { store.dismissPurchaseCelebration() } })) {
            PostPurchaseCelebrationView(context: store.purchaseCelebrationContext ?? .general) {
                store.dismissPurchaseCelebration()
            }
        }
    }

    private var openedBinding: Binding<Bool> {
        Binding(
            get: { openedProjectId != nil },
            set: { if !$0 { openedProjectId = nil } }
        )
    }

    private func tabView(
        selectedTab: Binding<iPadRootTab>,
        settingsPath: Binding<[iPadSettingsDestination]>
    ) -> some View {
        TabView(selection: selectedTab) {
            Tab("Projects", systemImage: "square.grid.2x2", value: iPadRootTab.projects) {
                NavigationStack {
                    ProjectsView(onOpen: openProject)
                        .navigationDestination(isPresented: openedBinding) {
                            // Push a lightweight gate first: it paints the spinner immediately
                            // (so the open never looks frozen) and builds the heavy editor only
                            // once the project's data has loaded. The spinner keeps animating on
                            // the render server even while the editor build stalls the main thread.
                            ProjectOpenGate(projectId: openedProjectId)
                                .toolbar(.hidden, for: .tabBar)
                        }
                }
            }

            Tab("Settings", systemImage: "gearshape", value: iPadRootTab.settings) {
                NavigationStack(path: settingsPath) {
                    IPadSettingsView()
                        .navigationDestination(for: iPadSettingsDestination.self) { destination in
                            switch destination {
                            case .appStoreConnect:
                                AppStoreConnectSettingsView()
                                    .navigationTitle("App Store Connect")
                                    .navigationBarTitleDisplayMode(.inline)
                            }
                        }
                }
            }
        }
    }

    private func openProject(_ id: UUID) {
        // Start the (off-main) load unless this is already the active/loaded project, then
        // push the gate. The gate paints the spinner immediately and builds the heavy editor
        // only once loading completes — so the cold first-open build never freezes a blank,
        // feedback-less screen.
        if id != state.activeProjectId {
            // Flip the opening flag up-front so the gate shows the spinner before the load
            // begins; switchToProject sets it again later (idempotent). selectProject runs off
            // this runloop turn so the push animates before the load work starts.
            state.beginProjectOpening()
            Task { @MainActor in
                await Task.yield()
                state.selectProject(id)
            }
        }
        openedProjectId = id
    }
}

/// Pushed in place of the editor when opening a project: shows the loading spinner right
/// away (so the open always has feedback), then reveals the real editor (`AppRootView`) once
/// the project's structural load finishes. The spinner is committed to the screen before the
/// editor is constructed, so it keeps animating on the render server even while the cold,
/// first-time editor build stalls the main thread.
private struct ProjectOpenGate: View {
    @Environment(AppState.self) private var state
    let projectId: UUID?
    @State private var showEditor = false

    /// Reveal on a positive "this project is loaded" condition rather than only the falling
    /// edge of `isOpeningProject`. If that flag were ever stranded true (e.g. a switch that
    /// no-ops), keying solely off it would hang the gate on a permanent spinner; and gating on
    /// `activeProjectId == projectId` ensures we never reveal a different project's editor.
    private var isReady: Bool {
        guard let projectId else { return false }
        return state.activeProjectId == projectId && !state.isOpeningProject
    }

    var body: some View {
        gateContent
            .task(id: isReady) {
                guard isReady, !showEditor else { return }
                // The spinner is already on screen (it's the gate's content during the
                // navigation push). Wait one frame so the cold first-time editor build lands
                // after the push settles; the spinner keeps animating on the render server
                // through the build's main-thread stall.
                try? await Task.sleep(for: .milliseconds(50))
                showEditor = true
            }
    }

    // AppRootView is the true branch of this conditional (not wrapped in a ZStack) so the
    // editor's `.inspector`/toolbar host resolution is unchanged from pushing it directly.
    @ViewBuilder
    private var gateContent: some View {
        if showEditor {
            AppRootView()
        } else {
            ZStack {
                Color.platformWindowBackground.ignoresSafeArea()
                ProjectLoadingOverlay(message: "Opening Project…")
            }
        }
    }
}

struct ProjectsView: View {
    @Environment(AppState.self) private var state
    @Environment(StoreService.self) private var store
    let onOpen: (UUID) -> Void

    @State private var showNewProject = false
    @State private var activeIdBeforeCreate: UUID?
    @State private var renamePrompt: ProjectNamePrompt?
    @State private var projectPendingDeletion: Project?

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 20)]

    var body: some View {
        Group {
            if state.visibleProjects.isEmpty {
                // Not wrapped in a ScrollView: NoProjectView (or the loading state) fills and centers.
                if !state.hasCompletedInitialLoad {
                    ProjectLoadingOverlay(message: "Loading from iCloud…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    emptyState
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(state.visibleProjects) { project in
                            Button {
                                onOpen(project.id)
                            } label: {
                                ProjectCard(project: project)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(ProjectCardButtonStyle())
                            .contentShape(Rectangle())
                            .accessibilityLabel(project.name)
                            .accessibilityHint("Opens the project")
                            .contextMenuWithPreview {
                                projectMenu(for: project)
                            } preview: {
                                ProjectContextMenuPreview(project: project)
                            }
                        }
                    }
                    .padding(24)
                }
            }
        }
        .background(Color.platformWindowBackground)
        .navigationTitle("Projects")
        .toolbar {
            if !store.isProUnlocked {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        store.presentPaywall(for: .general)
                    } label: {
                        Label("Upgrade to Pro", systemImage: "crown")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            // A spinner whenever iCloud sync is in progress (upload or download), so the
            // Projects screen always signals ongoing sync without a modal/blocking banner.
            // Kept on the trailing side so it isn't glued to the leading "Upgrade to Pro" button.
            if state.iCloudSyncStatus.isActive {
                ToolbarItem(placement: .topBarTrailing) {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Syncing with iCloud")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    newProject()
                } label: {
                    Label("New Project", systemImage: "plus")
                }
            }
        }
        .fullScreenCover(isPresented: $showNewProject, onDismiss: openNewlyCreatedProject) {
            NavigationStack {
                NewProjectWindowView()
            }
        }
        .sheet(item: $renamePrompt) { prompt in
            ProjectNameSheet(prompt: prompt)
        }
        .alert("Delete Project", isPresented: deletionBinding, presenting: projectPendingDeletion) { project in
            Button("Delete", role: .destructive) {
                state.deleteProject(project.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: { project in
            Text("Are you sure you want to delete \"\(project.name)\"? This cannot be undone.")
        }
    }

    private var emptyState: some View {
        NoProjectView(onCreate: newProject)
    }

    @ViewBuilder
    private func projectMenu(for project: Project) -> some View {
        Button("Open", systemImage: "arrow.up.forward.app") {
            onOpen(project.id)
        }

        Button("Rename…", systemImage: "pencil") {
            renamePrompt = ProjectNamePrompt(
                title: String(localized: "Rename Project"),
                confirmTitle: String(localized: "Rename"),
                initialValue: project.name
            ) { newName in
                state.renameProject(project.id, to: newName)
            }
        }

        Button("Duplicate…", systemImage: "plus.square.on.square") {
            store.requirePro(
                allowed: store.canCreateProject(currentCount: state.visibleProjects.count),
                context: .projectLimit
            ) {
                renamePrompt = ProjectNamePrompt(
                    title: String(localized: "Duplicate Project"),
                    confirmTitle: String(localized: "Duplicate"),
                    initialValue: project.name + " Copy"
                ) { newName in
                    state.duplicateProject(project.id, name: newName)
                }
            }
        }

        Divider()

        Button("Delete…", systemImage: "trash", role: .destructive) {
            projectPendingDeletion = project
        }
    }

    private var deletionBinding: Binding<Bool> {
        Binding(
            get: { projectPendingDeletion != nil },
            set: { if !$0 { projectPendingDeletion = nil } }
        )
    }

    private func newProject() {
        store.requirePro(
            allowed: store.canCreateProject(currentCount: state.visibleProjects.count),
            context: .projectLimit
        ) {
            activeIdBeforeCreate = state.activeProjectId
            showNewProject = true
        }
    }

    /// `NewProjectWindowView` sets the new project active on creation. If that changed
    /// while the sheet was up, jump straight into the editor for it.
    private func openNewlyCreatedProject() {
        guard let active = state.activeProjectId, active != activeIdBeforeCreate else { return }
        onOpen(active)
    }
}

private struct ProjectContextMenuPreview: View {
    let project: Project

    var body: some View {
        ProjectCard(project: project)
            .frame(width: 260, alignment: .leading)
            .contextMenuPreviewCard()
    }
}

private struct ProjectCard: View {
    let project: Project
    @State private var snapshot: Image?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Text(project.modifiedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .task(id: project.modifiedAt) {
            snapshot = await ProjectThumbnailService.thumbnail(for: project)
        }
    }

    private var thumbnail: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.22), Color.accentColor.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .overlay {
                if let snapshot {
                    snapshot
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "rectangle.on.rectangle.angled")
                        .font(.system(size: 34, weight: .regular))
                        .foregroundStyle(Color.accentColor.opacity(0.7))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            }
    }
}

/// Plain card rendering plus a subtle press-down scale for touch feedback (the Projects
/// home screen has no other affordance to show a tap registered).
private struct ProjectCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
#endif
