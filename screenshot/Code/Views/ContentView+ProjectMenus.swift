import StoreKit
import SwiftUI

extension ContentView {
    var sortedProjects: [Project] {
        let base = projectSortOrder == "alphabetical"
            ? state.visibleProjects.sortedByName()
            : state.visibleProjects
        return base.filter(\.isStarred) + base.filter { !$0.isStarred }
    }

    @ViewBuilder
    var projectSwitcherSection: some View {
        ForEach(sortedProjects) { project in
            Button {
                guard project.id != state.activeProjectId else { return }
                state.selectProject(project.id)
            } label: {
                if project.id == state.activeProjectId {
                    Label(project.name, systemImage: "checkmark")
                } else if project.isStarred {
                    Label(project.name, systemImage: "star.fill")
                } else {
                    Text(project.name)
                }
            }
        }
    }

    @ViewBuilder
    var currentProjectSection: some View {
        Section("Current Project") {
            Button("Rename Project...", systemImage: "pencil") {
                guard let id = state.activeProjectId else { return }
                let currentName = state.activeProject?.name ?? ""
                // Defer so the menu fully dismisses before the modal opens.
                Task { @MainActor in
                    presentProjectNameAlert(
                        title: String(localized: "Rename Project"),
                        confirmTitle: String(localized: "Rename"),
                        initialValue: currentName
                    ) { newName in
                        state.renameProject(id, to: newName)
                    }
                }
            }
            .disabled(state.activeProjectId == nil)

            let isStarred = state.activeProject?.isStarred == true
            Button(
                isStarred ? "Unstar Project" : "Star Project",
                systemImage: isStarred ? "star.slash" : "star"
            ) {
                guard let id = state.activeProjectId else { return }
                state.setProjectStarred(id, !isStarred)
            }
            .disabled(state.activeProjectId == nil)

            Button("Duplicate Project...", systemImage: "plus.square.on.square") {
                store.requirePro(
                    allowed: store.canCreateProject(currentCount: state.visibleProjects.count),
                    context: .projectLimit
                ) {
                    guard let id = state.activeProjectId else { return }
                    let initialName = (state.activeProject?.name ?? "") + " Copy"
                    Task { @MainActor in
                        presentProjectNameAlert(
                            title: String(localized: "Duplicate Project"),
                            confirmTitle: String(localized: "Duplicate"),
                            initialValue: initialName
                        ) { newName in
                            state.duplicateProject(id, name: newName)
                        }
                    }
                }
            }
            .disabled(state.activeProjectId == nil)

            Button("Reset Project...", systemImage: "arrow.counterclockwise", role: .destructive) {
                if confirmBeforeDeleting {
                    isResettingProject = true
                } else if let id = state.activeProjectId {
                    state.resetProject(id)
                }
            }
            .disabled(state.activeProjectId == nil)

            resetFromTemplateMenu

            Button("Delete Project...", systemImage: "trash", role: .destructive) {
                if confirmBeforeDeleting {
                    isDeletingProject = true
                } else if let id = state.activeProjectId {
                    state.deleteProject(id)
                }
            }
            .disabled(state.activeProjectId == nil)

            #if os(macOS)
            Menu("Project File", systemImage: "folder") {
                Button("Show in Finder", systemImage: "folder") {
                    guard let id = state.activeProjectId else { return }
                    let folder = PersistenceService.projectDirectoryURL(id)
                    PlatformReveal.inFileViewer([folder])
                }

                Button("Copy Project File Path", systemImage: "doc.on.clipboard") {
                    guard let id = state.activeProjectId else { return }
                    PlatformPasteboard.copyString(PersistenceService.projectDataURL(id).path)
                }

                Button("Copy AI Localization Prompt", systemImage: "character.bubble") {
                    guard let id = state.activeProjectId else { return }
                    PlatformPasteboard.copyString(LocalizationPromptService.prompt(forProjectId: id))
                }
            }
            .disabled(state.activeProjectId == nil)
            #endif
        }
    }

    func presentProjectNameAlert(
        title: String,
        confirmTitle: String,
        initialValue: String,
        onConfirm: @escaping (String) -> Void
    ) {
        projectNamePrompt = ProjectNamePrompt(
            title: title,
            confirmTitle: confirmTitle,
            initialValue: initialValue,
            onConfirm: onConfirm
        )
    }

    @ViewBuilder
    var resetFromTemplateMenu: some View {
        if !projectTemplates.isEmpty {
            Menu("Reset Project from Template", systemImage: "doc.on.doc") {
                ForEach(projectTemplates) { template in
                    Button {
                        resetTemplate = template
                        if confirmBeforeDeleting {
                            isResettingProject = true
                        } else if let id = state.activeProjectId {
                            state.resetProjectFromTemplate(id, template: template)
                            resetTemplate = nil
                        }
                    } label: {
                        Label {
                            Text(template.name)
                        } icon: {
                            if let icon = template.menuIcon {
                                Image(nsImage: icon)
                            }
                        }
                    }
                }
            }
            .disabled(state.activeProjectId == nil)
        }
    }

    var projectMenuLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            Text(state.activeProject?.name ?? "No Project")
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minWidth: 180, idealWidth: 240, maxWidth: 320, alignment: .leading)
        }
        .accessibilityIdentifier("projectPicker")
    }

    var projectSwitcherToolbarMenu: some View {
        Menu {
            projectMenuContent
        } label: {
            projectMenuLabel
        }
        .menuStyle(.button)
        .help(state.activeProject?.name ?? String(localized: "Switch project"))
        .accessibilityIdentifier("projectSwitcherMenu")
    }

    @ViewBuilder
    var projectMenuContent: some View {
        projectSwitcherSection
    }

    #if os(macOS)
    var projectActionsToolbarMenu: some View {
        Menu {
            Button("New Project...", systemImage: "plus") {
                store.requirePro(
                    allowed: store.canCreateProject(currentCount: state.visibleProjects.count),
                    context: .projectLimit
                ) {
                    openWindow(id: NewProjectWindowView.windowID)
                }
            }

            Divider()

            currentProjectSection
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("Project actions")
        .accessibilityIdentifier("projectActionsMenu")
    }
    #endif

    var inspectorToggleButton: some View {
        Button {
            isInspectorPresented.toggle()
        } label: {
            #if os(iOS)
            Label("Inspector", systemImage: horizontalSizeClass == .compact ? "slider.horizontal.3" : "sidebar.trailing")
            #else
            Label("Inspector", systemImage: "sidebar.trailing")
            #endif
        }
        .help(isInspectorPresented ? String(localized: "Hide inspector") : String(localized: "Show inspector"))
        .keyboardShortcut("i", modifiers: [.command, .option])
    }

    #if os(iOS)
    var editorModeFloatingButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                state.setViewMode(!state.isViewMode)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: state.isViewMode ? "hand.draw" : "pencil")
                    .contentTransition(.symbolEffect(.replace))
                Text(state.isViewMode ? "View" : "Edit")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(state.isViewMode ? Color.white : Color.accentColor)
            .padding(.horizontal, UIMetrics.ProminentCapsule.horizontalPadding)
            .frame(height: 44)
            .editorModeFloatingButtonBackground(active: state.isViewMode)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: state.isViewMode)
        .help(state.isViewMode ? String(localized: "Switch to Edit mode") : String(localized: "Switch to View mode (pan & zoom only)"))
        .accessibilityLabel(state.isViewMode ? Text("Switch to Edit mode") : Text("Switch to View mode"))
    }

    // The principal (title) toolbar slot strips button styles, so the Liquid Glass
    // capsule is applied to the label itself rather than via .glassProminent.
    var iPadBuyProButton: some View {
        Button {
            store.presentPaywall(for: .general)
        } label: {
            buyProGlassLabel
        }
        .buttonStyle(.plain)
        .help("Unlock all projects, rows, and templates")
    }

    private var buyProGlassLabel: some View {
        Label("Buy Pro", systemImage: "crown")
            .labelStyle(.titleAndIcon)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, UIMetrics.ProminentCapsule.horizontalPadding)
            .padding(.vertical, UIMetrics.ProminentCapsule.verticalPadding)
            .glassProminentCapsule()
    }

    var iPadProjectTitleMenu: some View {
        Menu {
            currentProjectSection
        } label: {
            HStack(spacing: 4) {
                Text(state.activeProject?.name ?? "No Project")
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 280)
        }
        .disabled(state.activeProjectId == nil)
        .help("Project actions")
        .accessibilityIdentifier("iPadProjectTitleMenu")
    }

    @ViewBuilder
    var iPadZoomMenu: some View {
        let presets: [CGFloat] = [0.5, 0.75, 1.0, 1.5, 2.0]

        Menu {
            Button("Fit to Editor", systemImage: "arrow.up.left.and.arrow.down.right") {
                fitZoomToWindow()
            }
            .disabled(state.rows.isEmpty)

            Button("Actual Size", systemImage: "magnifyingglass") {
                state.resetZoom()
            }
            .disabled(abs(state.zoomLevel - 1.0) < 0.001)

            Divider()

            Button("Zoom Out", systemImage: "minus.magnifyingglass") {
                state.zoomOut()
            }
            .disabled(state.zoomLevel <= ZoomConstants.min)

            Button("Zoom In", systemImage: "plus.magnifyingglass") {
                state.zoomIn()
            }
            .disabled(state.zoomLevel >= ZoomConstants.max)

            Divider()

            Section("Presets") {
                ForEach(presets, id: \.self) { preset in
                    Button {
                        state.setZoomLevel(preset)
                    } label: {
                        let title = "\(Int((preset * 100).rounded()))%"
                        if abs(state.zoomLevel - preset) < 0.001 {
                            Label(title, systemImage: "checkmark")
                        } else {
                            Text(title)
                        }
                    }
                }
            }
        } label: {
            Label {
                Text("\(Int((state.zoomLevel * 100).rounded()))%")
                    .monospacedDigit()
            } icon: {
                Image(systemName: "magnifyingglass")
            }
        }
        .help("Zoom options")
    }

    var iPadUndoButton: some View {
        Button {
            state.undoDocumentAction()
        } label: {
            Label("Undo", systemImage: "arrow.uturn.backward")
        }
        .disabled(!state.canUndoDocumentAction)
        .help("Undo")
    }

    var iPadRedoButton: some View {
        Button {
            state.redoDocumentAction()
        } label: {
            Label("Redo", systemImage: "arrow.uturn.forward")
        }
        .disabled(!state.canRedoDocumentAction)
        .help("Redo")
    }
    #endif
}

extension View {
    @ViewBuilder
    func iPadToolbarProminentStyle() -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
        #else
        self
        #endif
    }

    /// Label-level counterpart of `iPadToolbarProminentStyle()` for slots that
    /// strip ButtonStyle (e.g. the principal toolbar slot).
    @ViewBuilder
    func glassProminentCapsule() -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            glassEffect(.regular.tint(.accentColor).interactive())
        } else {
            background(Color.accentColor, in: Capsule())
        }
        #else
        background(Color.accentColor, in: Capsule())
        #endif
    }

    /// Circular background for the editor-mode FAB: accent-tinted glass when
    /// active (view mode), neutral glass when inactive (edit mode).
    @ViewBuilder
    func editorModeFloatingButtonBackground(active: Bool) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            // Liquid Glass provides its own elevation — no manual shadow.
            glassEffect(active ? .regular.tint(.accentColor).interactive() : .regular.interactive(), in: .capsule)
        } else {
            background(active ? Color.accentColor : Color.platformWindowBackground, in: Capsule())
                .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
        }
        #else
        background(active ? Color.accentColor : Color.platformWindowBackground, in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
        #endif
    }
}
