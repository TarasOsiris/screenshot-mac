import SwiftUI

struct NewProjectWindowView: View {
    static let windowID = "new-project"

    @Environment(AppState.self) private var state
    @Environment(StoreService.self) private var store
    @Environment(\.dismiss) private var dismiss
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    private let templateGridSpacing: CGFloat = 8
    private let templateGridHorizontalPadding: CGFloat = 8

    @State private var projectName = ""
    @State private var creationMode: NewProjectCreationMode = .template
    @State private var selectedTemplateId: String?
    @State private var rowDrafts: [BlankProjectRowDraft] = []
    @State private var templates: [ProjectTemplate] = []
    @FocusState private var isNameFieldFocused: Bool

    private var selectedTemplate: ProjectTemplate? {
        guard let selectedTemplateId else { return nil }
        return templates.first(where: { $0.id == selectedTemplateId })
    }

    private var createButtonTitle: LocalizedStringKey {
        creationMode == .blank ? "Create Blank Project" : "Create from Template"
    }

    var body: some View {
        platformContent
            .onAppear(perform: prepareInitialState)
    }

    #if os(macOS)
    private var platformContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 16) {
                projectNameField
                NewProjectModePicker(selectedMode: $creationMode)

                Group {
                    switch creationMode {
                    case .blank:
                        BlankProjectConfigurator(rowDrafts: $rowDrafts)
                    case .template:
                        NewProjectTemplateConfigurator(
                            templates: templates,
                            selectedTemplateId: $selectedTemplateId,
                            columns: templateGridColumns,
                            spacing: templateGridSpacing,
                            horizontalPadding: templateGridHorizontalPadding
                        )
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: creationMode)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(18)
            .background(Color.platformControlBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            footer
        }
        .padding(22)
        .frame(minWidth: 760, idealWidth: 760, minHeight: 620, idealHeight: 620)
    }
    #else
    // iPad presents this as a dedicated full-screen page: a native grouped Form with
    // section headers, and Cancel/Create in the navigation bar instead of an inline footer.
    private var platformContent: some View {
        Form {
            Section("Name") {
                TextField("Project name", text: $projectName)
                    .focused($isNameFieldFocused)
                    .submitLabel(.done)
            }

            Section("Create From") {
                Picker("Create From", selection: $creationMode) {
                    Text("Template").tag(NewProjectCreationMode.template)
                    Text("Blank").tag(NewProjectCreationMode.blank)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            switch creationMode {
            case .template:
                NewProjectTemplateSection(
                    templates: templates,
                    selectedTemplateId: $selectedTemplateId,
                    columns: templateGridColumns,
                    spacing: templateGridSpacing
                )
            case .blank:
                BlankProjectSection(rowDrafts: $rowDrafts)
            }
        }
        .navigationTitle("New Project")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") { createProject() }
                    .fontWeight(.semibold)
                    .iPadToolbarProminentStyle()
                    .disabled(!canCreateProject)
            }
        }
    }

    #endif

    #if os(macOS)
    private var projectNameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Name")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("Project name", text: $projectName)
                .textFieldStyle(.roundedBorder)
                .focused($isNameFieldFocused)
        }
    }

    private var footer: some View {
        HStack {
            Button("Cancel", role: .cancel) {
                dismiss()
            }
            .keyboardShortcut(.escape)

            Spacer()

            Button(createButtonTitle) {
                createProject()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canCreateProject)
            .keyboardShortcut(.return)
        }
    }
    #endif

    private var canCreateProject: Bool {
        switch creationMode {
        case .blank:
            !rowDrafts.isEmpty
        case .template:
            selectedTemplate != nil
        }
    }

    private var templateGridColumns: [GridItem] {
        #if os(iOS)
        let compact = horizontalSizeClass == .compact
        #else
        let compact = false
        #endif
        return .adaptiveCards(minimum: 230, maximum: 320, spacing: templateGridSpacing, compact: compact)
    }

    private func prepareInitialState() {
        Task {
            templates = await TemplateService.availableTemplatesAsync()
            if selectedTemplateId == nil {
                selectedTemplateId = templates.first?.id
            }
        }
        projectName = "Project \(state.visibleProjects.count + 1)"
        creationMode = .template
        rowDrafts = [
            BlankProjectRowDraft(category: .iphone),
            BlankProjectRowDraft(category: .ipadPro13),
            BlankProjectRowDraft(category: .androidPhone),
        ]
        #if os(macOS)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isNameFieldFocused = true
        }
        #endif
    }

    private func createProject() {
        guard store.canCreateProject(currentCount: state.visibleProjects.count) else {
            // Free-tier limit reached after this view opened (e.g. an iCloud sync added a
            // project). Show the paywall; on iPad it's hosted at the navigation root, behind
            // this full-screen cover, so close the cover to let it present.
            store.presentPaywall(for: .projectLimit)
            #if os(iOS)
            dismiss()
            #endif
            return
        }

        let trimmedName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? "Project \(state.visibleProjects.count + 1)" : trimmedName

        switch creationMode {
        case .blank:
            let configurations = rowDrafts.map(\.configuration)
            state.createBlankProject(name: resolvedName, rowConfigurations: configurations)
        case .template:
            guard let selectedTemplate else { return }
            state.createProjectFromTemplate(selectedTemplate, name: resolvedName)
        }

        AppWindowManager.shared.showMainWindow()
        dismiss()
    }
}
