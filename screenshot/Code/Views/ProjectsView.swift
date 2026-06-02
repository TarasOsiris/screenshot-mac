#if os(iOS)
import SwiftUI

/// iPad root: a tab bar with Projects (a home screen listing every project) and Settings.
/// Opening a project pushes the editor (`AppRootView`) onto an *outer* NavigationStack that
/// wraps the whole tab view — so the push covers the entire tab view as one unit (the tab bar
/// is never hidden/re-shown, which made the tab items flash/reflow on return) while keeping a
/// smooth, UIKit-driven horizontal slide that doesn't freeze the way an inline SwiftUI
/// transition does (it builds the heavy editor synchronously inside the animation).
struct iPadRootView: View {
    @Environment(AppState.self) private var state
    @Environment(StoreService.self) private var store
    @State private var openedProjectId: UUID?

    var body: some View {
        NavigationStack {
            tabView
                // Outer stack reserves an empty nav bar around the tab view; hide it so only the
                // tabs' own inner nav bars (Projects/Settings titles + toolbars) show.
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(isPresented: openedBinding) {
                    AppRootView()
                }
        }
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
        .sheet(isPresented: Binding(get: { store.showPaywall }, set: { _ in store.dismissPaywall() }),
               onDismiss: { store.presentPendingCelebrationIfNeeded() }) {
            PaywallSheetContent(store: store)
        }
        .sheet(isPresented: Binding(get: { store.purchaseCelebrationContext != nil }, set: { if !$0 { store.dismissPurchaseCelebration() } })) {
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

    private var tabView: some View {
        TabView {
            Tab("Projects", systemImage: "square.grid.2x2") {
                NavigationStack {
                    ProjectsView(onOpen: openProject)
                }
            }

            Tab("Settings", systemImage: "gearshape") {
                NavigationStack {
                    IPadSettingsView()
                }
            }
        }
    }

    private func openProject(_ id: UUID) {
        // Reveal the editor immediately so the loading overlay (driven by
        // `isOpeningProject`) paints right away — the menu must never look frozen
        // while a large project decodes.
        openedProjectId = id
        guard id != state.activeProjectId else { return }  // already loaded, no reload
        state.beginProjectOpening()
        // Defer the switch one runloop turn so the push + overlay render before the
        // (brief, main-thread) save of the previously-active project runs.
        Task { @MainActor in
            await Task.yield()
            state.selectProject(id)
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
        ScrollView {
            if state.visibleProjects.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: columns, spacing: 24) {
                    ForEach(state.visibleProjects) { project in
                        Button {
                            onOpen(project.id)
                        } label: {
                            ProjectCard(project: project)
                        }
                        .buttonStyle(ProjectCardButtonStyle())
                        .accessibilityLabel(project.name)
                        .accessibilityHint("Opens the project")
                        .contextMenu { projectMenu(for: project) }
                    }
                }
                .padding(24)
            }
        }
        .background(Color.platformWindowBackground)
        .navigationTitle("Projects")
        .toolbar {
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
                .presentationSizing(.fitted)
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
        ContentUnavailableView {
            Label("No Projects", systemImage: "square.on.square.dashed")
        } description: {
            Text("Create your first project to start designing screenshots.")
        } actions: {
            Button("New Project") { newProject() }
                .buttonStyle(.borderedProminent)
        }
        .padding(.top, 80)
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
                allowed: store.canCreateProject(),
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
        .disabled(state.visibleProjects.count <= 1)
    }

    private var deletionBinding: Binding<Bool> {
        Binding(
            get: { projectPendingDeletion != nil },
            set: { if !$0 { projectPendingDeletion = nil } }
        )
    }

    private func newProject() {
        store.requirePro(
            allowed: store.canCreateProject(),
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
        .task(id: project.modifiedAt) {
            snapshot = ProjectThumbnailService.thumbnail(for: project)
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
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
#endif
