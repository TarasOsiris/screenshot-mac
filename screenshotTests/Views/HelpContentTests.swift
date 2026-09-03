import Foundation
@testable import Screenshot_Bro
import SwiftUI
import Testing

#if os(macOS)
/// The Help window is hand-written prose, so nothing fails a build when a feature ships
/// undocumented or a documented control is renamed. These pin the parts that *can* be checked
/// mechanically — the rest still relies on the CLAUDE.md sync rule.
@MainActor
struct HelpContentTests {
    @Test func everySectionHasContent() {
        for section in HelpSection.allCases {
            let entry = section.entry
            #expect(!entry.blocks.isEmpty, "\(section.rawValue) has no content blocks")
            #expect(!entry.title.helpResolved.isEmpty, "\(section.rawValue) has no title")
        }
    }

    @Test func sidebarLabelsAreUsable() {
        var icons: Set<String> = []
        for section in HelpSection.allCases {
            #expect(!section.title.helpResolved.isEmpty)
            #expect(!section.icon.isEmpty)
            #expect(icons.insert(section.icon).inserted, "duplicate icon \(section.icon)")
        }
    }

    /// Key caps are ordinary blocks, so the shortcuts page is searchable like any other topic.
    @Test func shortcutsPageIsBuiltFromBlocks() {
        let rows = HelpSection.shortcuts.shortcutRows
        #expect(!rows.isEmpty)
        #expect(HelpSection.shortcuts.entry.blocks.contains { if case .shortcutRows = $0 { true } else { false } })
    }

    @Test func noShortcutIsListedTwice() {
        var seen: Set<String> = []
        for row in HelpSection.shortcuts.shortcutRows {
            #expect(seen.insert(row.keys).inserted, "shortcut '\(row.keys)' is listed twice")
        }
    }

    /// The free-tier numbers are restated as prose in three sections. If a limit changes, the
    /// prose has to change with it.
    @Test func freeTierNumbersMatchTheStore() {
        let text = HelpSection.proFeatures.entry.blocks.map(\.searchText).joined(separator: "\n")
        #expect(text.contains("\(StoreService.freeMaxProjects) project"))
        #expect(text.contains("\(StoreService.freeMaxRows) rows"))
        #expect(text.contains("\(StoreService.freeMaxTemplatesPerRow) templates"))

        #expect(HelpSection.rows.entry.blocks.map(\.searchText).joined()
            .contains("\(StoreService.freeMaxRows) rows"))
        #expect(HelpSection.templates.entry.blocks.map(\.searchText).joined()
            .contains("\(StoreService.freeMaxTemplatesPerRow) templates"))
    }

    /// Adding a device category or a showcase preset should mean documenting it, the same way
    /// CLAUDE.md already requires updating every switch over these enums.
    @Test func everyDeviceCategoryIsDocumented() {
        let text = HelpSection.rows.entry.blocks.map(\.searchText).joined(separator: "\n")
        for category in DeviceCategory.allCases {
            #expect(text.contains(category.label), "device category '\(category.label)' is undocumented")
        }
    }

    @Test func everyShowcaseAspectPresetIsDocumented() {
        let text = HelpSection.showcase.entry.blocks.map(\.searchText).joined(separator: "\n")
        for ratio in ShowcaseAspectPreset.allCases {
            #expect(text.contains(ratio.label), "showcase aspect preset '\(ratio.label)' is undocumented")
        }
    }

    // MARK: - Search

    @Test func searchFindsTheTopicBehindASupportQuestion() {
        // The 4.10 ticket: a customer could not find drop shadow, which Help documented all along.
        #expect(HelpSection.matching("shadow").contains(.shapes))
        #expect(HelpSection.matching("stretch across").contains(.rows))
        #expect(HelpSection.matching("recovered project").contains(.projects))
    }

    /// `matching` takes an already-trimmed needle — `HelpView` trims once per keystroke rather
    /// than once per section.
    @Test func searchIsCaseAndDiacriticInsensitive() {
        #expect(HelpSection.matching("SHADOW") == HelpSection.matching("shadow"))
        #expect(HelpSection.matching("") == HelpSection.allCases)
        #expect(HelpSection.matching("zzzznotathing").isEmpty)
    }

    @Test func searchReachesTheShortcutsPage() {
        #expect(HelpSection.matching("Nudge selection").contains(.shortcuts))
    }

    @Test func aMatchedSectionCanScrollToItsBlock() {
        #expect(HelpSection.shapes.firstMatchingBlockIndex("Drop shadow") != nil)
        // Previously guarded off: the shortcuts page now scrolls to a match like every other.
        #expect(HelpSection.shortcuts.firstMatchingBlockIndex("Nudge selection") != nil)
        #expect(HelpSection.shapes.firstMatchingBlockIndex("") == nil)
    }

    // MARK: - Cross-references

    @Test func everySeeAlsoPointsAwayFromItsOwnSection() {
        for section in HelpSection.allCases {
            let targets = section.entry.seeAlso
            #expect(!targets.isEmpty, "\(section.rawValue) has no related topics")
            #expect(!targets.contains(section), "\(section.rawValue) links to itself")
            #expect(Set(targets).count == targets.count, "\(section.rawValue) repeats a link")
        }
    }
}
#endif
