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
        ShortcutGroup(title: LocalizedStringResource("shortcutGroup.file", defaultValue: "File", comment: "Keyboard Shortcuts help heading, named after the macOS File menu"), rows: [
            ShortcutRowItem(keys: "⌘N", description: "New project"),
            ShortcutRowItem(keys: "⌘E", description: "Export screenshots"),
        ]),
        ShortcutGroup(title: LocalizedStringResource("shortcutGroup.edit", defaultValue: "Edit", comment: "Keyboard Shortcuts help heading, named after the macOS Edit menu"), rows: [
            ShortcutRowItem(keys: "⌘Z", description: "Undo"),
            ShortcutRowItem(keys: "⌘⇧Z", description: "Redo"),
            ShortcutRowItem(keys: "⌘C", description: "Copy selected shapes, or focused text"),
            ShortcutRowItem(keys: "⌘X", description: "Cut focused text"),
            ShortcutRowItem(keys: "⌘V", description: "Paste shapes, images, SVGs, or focused text"),
            ShortcutRowItem(keys: "⌘A", description: "Select all shapes in the active row, or focused text"),
            ShortcutRowItem(keys: "⌘D", description: "Duplicate selected shapes / row"),
            ShortcutRowItem(keys: "⌘L", description: "Lock or unlock selected shapes"),
            ShortcutRowItem(keys: String(localized: "shortcutKey.delete", defaultValue: "Delete", comment: "Name of the Delete key on a Mac keyboard, in the Keyboard Shortcuts help"), description: "Delete selected shapes"),
            ShortcutRowItem(keys: String(localized: "Esc", comment: "Name of the Escape key on a Mac keyboard, in the Keyboard Shortcuts help"), description: "Deselect"),
            ShortcutRowItem(keys: "⌘⇧]", description: "Bring shape to front"),
            ShortcutRowItem(keys: "⌘⇧[", description: "Send shape to back"),
            ShortcutRowItem(keys: "← → ↑ ↓", description: "Nudge selection by 1px"),
            ShortcutRowItem(keys: String(localized: "⇧ + Arrow", comment: "Key or gesture in the Keyboard Shortcuts help"), description: "Nudge selection by 10px"),
            ShortcutRowItem(keys: String(localized: "⌥ + Drag", comment: "Key or gesture in the Keyboard Shortcuts help"), description: "Duplicate while dragging"),
            ShortcutRowItem(keys: String(localized: "⇧ + Drag rotation handle", comment: "Key or gesture in the Keyboard Shortcuts help"), description: "Snap rotation to 15° steps"),
            ShortcutRowItem(keys: String(localized: "⇧ + Drag resize handle", comment: "Key or gesture in the Keyboard Shortcuts help"), description: "Lock aspect ratio"),
        ]),
        ShortcutGroup(title: LocalizedStringResource("shortcutGroup.view", defaultValue: "View", comment: "Keyboard Shortcuts help heading, named after the macOS View menu"), rows: [
            ShortcutRowItem(keys: "⌘+", description: "Zoom in"),
            ShortcutRowItem(keys: "⌘−", description: "Zoom out"),
            ShortcutRowItem(keys: "⌘0", description: "Reset to default zoom"),
            ShortcutRowItem(keys: "⌘⌥I", description: "Show or hide the inspector"),
            ShortcutRowItem(keys: "F", description: "Focus on selection"),
            ShortcutRowItem(keys: String(localized: "Pinch / ⌘ + Scroll", comment: "Key or gesture in the Keyboard Shortcuts help"), description: "Zoom canvas"),
            ShortcutRowItem(keys: String(localized: "Middle-click + drag", comment: "Key or gesture in the Keyboard Shortcuts help"), description: "Pan canvas"),
        ]),
        ShortcutGroup(title: "Language", rows: [
            ShortcutRowItem(keys: String(localized: "Language menu", comment: "The toolbar Language menu, listed as a key in the Keyboard Shortcuts help"), description: "Lists every language you've added, plus every translation action"),
            ShortcutRowItem(keys: "⌘]", description: "Next language"),
            ShortcutRowItem(keys: "⌘[", description: "Previous language"),
            ShortcutRowItem(keys: "⌘⌥0", description: "Switch to base language"),
        ]),
        ShortcutGroup(title: "Text editing", rows: [
            ShortcutRowItem(keys: String(localized: "Double-click text", comment: "Key or gesture in the Keyboard Shortcuts help"), description: "Enter inline edit mode"),
            ShortcutRowItem(keys: String(localized: "Esc / click outside", comment: "Key or gesture in the Keyboard Shortcuts help"), description: "Commit text edit"),
        ]),
        ShortcutGroup(title: LocalizedStringResource("shortcutGroup.window", defaultValue: "Window", comment: "Keyboard Shortcuts help heading, named after the macOS Window menu"), rows: [
            ShortcutRowItem(keys: String(localized: "Window ▸ Show Main Window", comment: "Menu path: the macOS Window menu, then its Show Main Window command. Match those menu titles."), description: "Bring the editor back when its window is closed"),
        ]),
        ShortcutGroup(title: "App", rows: [
            ShortcutRowItem(keys: "⌘,", description: "Open Settings"),
            ShortcutRowItem(keys: "⌘?", description: "Open Screenshot Bro Help"),
        ]),
    ]
}
#endif
