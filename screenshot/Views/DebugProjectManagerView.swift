#if DEBUG
import SwiftUI

struct DebugProjectManagerView: View {
    @Bindable var state: AppState
    @State private var selection: Set<UUID> = []
    @State private var isConfirmingDelete = false
    @Environment(\.dismiss) private var dismiss

    private var sortedProjects: [Project] {
        state.visibleProjects.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("\(sortedProjects.count) projects")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Select All") {
                    selection = Set(sortedProjects.map(\.id))
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11))

                Button("Deselect All") {
                    selection.removeAll()
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
                .disabled(selection.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Project list
            List(sortedProjects, selection: $selection) { project in
                HStack(spacing: 8) {
                    if project.id == state.activeProjectId {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(.green)
                    } else {
                        Image(systemName: "circle")
                            .font(.system(size: 6))
                            .foregroundStyle(.quaternary)
                    }

                    Text(project.name)
                        .font(.system(size: 12))
                        .lineLimit(1)

                    Spacer()

                    Text(project.modifiedAt, style: .date)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .tag(project.id)
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            Divider()

            // Actions bar
            HStack {
                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Label("Delete \(selection.count) selected", systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(selection.isEmpty)
                .foregroundStyle(selection.isEmpty ? Color.secondary : Color.red)

                Spacer()

                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 420, height: 400)
        .alert("Delete \(selection.count) project\(selection.count == 1 ? "" : "s")?", isPresented: $isConfirmingDelete) {
            Button("Delete", role: .destructive) {
                deleteSelected()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }

    private func deleteSelected() {
        // Delete non-active projects first, active last (triggers switch)
        let activeId = state.activeProjectId
        for id in selection where id != activeId {
            state.deleteProject(id)
        }
        if let activeId, selection.contains(activeId) {
            state.deleteProject(activeId)
        }
        selection.removeAll()
    }
}
#endif
