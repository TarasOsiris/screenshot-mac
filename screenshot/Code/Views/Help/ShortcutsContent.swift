import SwiftUI

#if os(macOS)
extension HelpSection {
    /// Key caps expressed as ordinary blocks, so this page searches, highlights and scrolls to a
    /// match exactly like a prose topic.
    var shortcutsEntry: HelpEntry {
        HelpEntry(
            title: "Keyboard Shortcuts",
            subtitle: "Mac keyboard shortcuts and canvas gestures.",
            blocks: Self.shortcutGroups.flatMap { group -> [HelpBlock] in
                [.heading(group.title), .shortcutRows(group.rows)]
            },
            seeAlso: [.editing, .shapes]
        )
    }

    /// Flattened key caps, for tests and any future "all shortcuts" surface.
    var shortcutRows: [ShortcutRowItem] { Self.shortcutGroups.flatMap(\.rows) }

    private struct ShortcutGroup {
        let title: LocalizedStringResource
        let rows: [ShortcutRowItem]
    }

    private static let shortcutGroups: [ShortcutGroup] = [
        ShortcutGroup(title: "File", rows: [
            ShortcutRowItem(keys: "⌘N", description: "New project"),
            ShortcutRowItem(keys: "⌘E", description: "Export screenshots"),
        ]),
        ShortcutGroup(title: "Edit", rows: [
            ShortcutRowItem(keys: "⌘Z", description: "Undo"),
            ShortcutRowItem(keys: "⌘⇧Z", description: "Redo"),
            ShortcutRowItem(keys: "⌘C", description: "Copy selected shapes, or focused text"),
            ShortcutRowItem(keys: "⌘X", description: "Cut focused text"),
            ShortcutRowItem(keys: "⌘V", description: "Paste shapes, images, SVGs, or focused text"),
            ShortcutRowItem(keys: "⌘A", description: "Select all shapes in the active row, or focused text"),
            ShortcutRowItem(keys: "⌘D", description: "Duplicate selected shapes / row"),
            ShortcutRowItem(keys: "⌘L", description: "Lock or unlock selected shapes"),
            ShortcutRowItem(keys: "Delete", description: "Delete selected shapes"),
            ShortcutRowItem(keys: "Esc", description: "Deselect"),
            ShortcutRowItem(keys: "⌘⇧]", description: "Bring shape to front"),
            ShortcutRowItem(keys: "⌘⇧[", description: "Send shape to back"),
            ShortcutRowItem(keys: "← → ↑ ↓", description: "Nudge selection by 1px"),
            ShortcutRowItem(keys: "⇧ + Arrow", description: "Nudge selection by 10px"),
            ShortcutRowItem(keys: "⌥ + Drag", description: "Duplicate while dragging"),
            ShortcutRowItem(keys: "⇧ + Drag rotation handle", description: "Snap rotation to 15° steps"),
            ShortcutRowItem(keys: "⇧ + Drag resize handle", description: "Lock aspect ratio"),
        ]),
        ShortcutGroup(title: "View", rows: [
            ShortcutRowItem(keys: "⌘+", description: "Zoom in"),
            ShortcutRowItem(keys: "⌘−", description: "Zoom out"),
            ShortcutRowItem(keys: "⌘0", description: "Reset to default zoom"),
            ShortcutRowItem(keys: "⌘⌥I", description: "Show or hide the inspector"),
            ShortcutRowItem(keys: "F", description: "Focus on selection"),
            ShortcutRowItem(keys: "Pinch / ⌘ + Scroll", description: "Zoom canvas"),
            ShortcutRowItem(keys: "Middle-click + drag", description: "Pan canvas"),
        ]),
        ShortcutGroup(title: "Language", rows: [
            ShortcutRowItem(keys: "Language menu", description: "Lists every language you've added, plus every translation action"),
            ShortcutRowItem(keys: "⌘]", description: "Next language"),
            ShortcutRowItem(keys: "⌘[", description: "Previous language"),
            ShortcutRowItem(keys: "⌘⌥0", description: "Switch to base language"),
        ]),
        ShortcutGroup(title: "Text editing", rows: [
            ShortcutRowItem(keys: "Double-click text", description: "Enter inline edit mode"),
            ShortcutRowItem(keys: "Esc / click outside", description: "Commit text edit"),
        ]),
        ShortcutGroup(title: "Window", rows: [
            ShortcutRowItem(keys: "Window ▸ Show Main Window", description: "Bring the editor back when its window is closed"),
        ]),
        ShortcutGroup(title: "App", rows: [
            ShortcutRowItem(keys: "⌘,", description: "Open Settings"),
            ShortcutRowItem(keys: "⌘?", description: "Open Screenshot Bro Help"),
        ]),
    ]
}
#endif
