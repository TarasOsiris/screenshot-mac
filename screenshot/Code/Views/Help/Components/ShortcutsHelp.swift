import SwiftUI

#if os(macOS)
struct ShortcutsHelp: View {
    struct Group {
        let title: LocalizedStringKey
        let rows: [(keys: String, description: LocalizedStringKey)]
    }

    private let groups: [Group] = [
        Group(title: "File", rows: [
            ("⌘N", "New project"),
            ("⌘E", "Export screenshots")
        ]),
        Group(title: "Edit", rows: [
            ("⌘Z", "Undo"),
            ("⌘⇧Z", "Redo"),
            ("⌘C", "Copy selected shapes, or focused text"),
            ("⌘X", "Cut focused text"),
            ("⌘V", "Paste shapes, images, SVGs, or focused text"),
            ("⌘A", "Select all shapes in the active row, or focused text"),
            ("⌘D", "Duplicate selected shapes / row"),
            ("⌘L", "Lock or unlock selected shapes"),
            ("Delete", "Delete selected shapes"),
            ("Esc", "Deselect"),
            ("⌘⇧]", "Bring shape to front"),
            ("⌘⇧[", "Send shape to back"),
            ("← → ↑ ↓", "Nudge selection by 1px"),
            ("⇧ + Arrow", "Nudge selection by 10px"),
            ("⌥ + Drag", "Duplicate while dragging"),
        ]),
        Group(title: "View", rows: [
            ("⌘+", "Zoom in"),
            ("⌘−", "Zoom out"),
            ("⌘0", "Reset to default zoom"),
            ("⌘⌥I", "Show or hide the inspector"),
            ("F", "Focus on selection"),
            ("Pinch / ⌘ + Scroll", "Zoom canvas"),
            ("Middle-click + drag", "Pan canvas"),
        ]),
        Group(title: "Language", rows: [
            ("⌘]", "Next language"),
            ("⌘[", "Previous language"),
            ("⌘⌥0", "Switch to base language"),
        ]),
        Group(title: "Text editing", rows: [
            ("Double-click text", "Enter inline edit mode"),
            ("Esc / click outside", "Commit text edit"),
        ]),
        Group(title: "App", rows: [
            ("⌘,", "Open Settings"),
            ("⌘?", "Open Screenshot Bro Help"),
        ]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HelpHeader("Keyboard Shortcuts", subtitle: "Mac keyboard shortcuts and canvas gestures.")
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                VStack(alignment: .leading, spacing: 8) {
                    HelpHeading(group.title, topPadding: 0)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(group.rows.enumerated()), id: \.offset) { _, row in
                            ShortcutRow(keys: row.keys, description: row.description)
                        }
                    }
                }
            }
        }
    }
}
#endif
