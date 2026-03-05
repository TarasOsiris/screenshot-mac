import SwiftUI

struct AppHeader: View {
    @Bindable var state: AppState
    @State private var isShowingProjectPicker = false
    @State private var editingProjectId: UUID?
    @State private var editingName = ""
    @State private var newProjectName = ""

    var body: some View {
        HStack(spacing: 12) {
            // Logo
            HStack(spacing: 6) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.blue)
                Text("Screenshot Mac")
                    .font(.system(size: 13, weight: .semibold))
            }

            Spacer()

            // Project selector
            Menu {
                ForEach(state.projects) { project in
                    Button {
                        state.selectProject(project.id)
                    } label: {
                        HStack {
                            Text(project.name)
                            if project.id == state.activeProjectId {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                Divider()
                Button("New Project...") {
                    state.createProject(name: "Project \(state.projects.count + 1)")
                }
            } label: {
                HStack(spacing: 4) {
                    Text(state.activeProject?.name ?? "No Project")
                        .font(.system(size: 12))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            Spacer()

            // Placeholder right section
            HStack(spacing: 8) {
                Button {
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .disabled(true)

                Button {
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .disabled(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
