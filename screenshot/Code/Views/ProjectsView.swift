#if os(iOS)
import SwiftUI

/// iPad root: a Projects home screen that lists every project. Opening one pushes
/// the editor (`AppRootView`) onto the stack; the back button returns here.
struct iPadRootView: View {
    @Environment(AppState.self) private var state
    @State private var openedProjectId: UUID?

    var body: some View {
        NavigationStack {
            ProjectsView(onOpen: openProject)
                .navigationDestination(isPresented: openedBinding) {
                    AppRootView()
                }
        }
    }

    private var openedBinding: Binding<Bool> {
        Binding(
            get: { openedProjectId != nil },
            set: { if !$0 { openedProjectId = nil } }
        )
    }

    private func openProject(_ id: UUID) {
        state.selectProject(id)
        openedProjectId = id
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
                        .buttonStyle(.plain)
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
        .sheet(isPresented: $showNewProject, onDismiss: openNewlyCreatedProject) {
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
                Image(systemName: "rectangle.on.rectangle.angled")
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(Color.accentColor.opacity(0.7))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            }
    }
}
#endif
