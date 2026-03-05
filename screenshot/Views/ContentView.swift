import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state
    @State private var isInspectorPresented = true

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                ForEach(state.rows) { row in
                    EditorRowView(state: state, row: row)
                    Divider()
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        state.addRow()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 12))
                        Text("Add Row")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 16)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .inspector(isPresented: $isInspectorPresented) {
            InspectorPanel(state: state)
                .inspectorColumnWidth(min: 220, ideal: 260, max: 320)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
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
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    isInspectorPresented.toggle()
                } label: {
                    Label("Toggle Inspector", systemImage: "sidebar.trailing")
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
