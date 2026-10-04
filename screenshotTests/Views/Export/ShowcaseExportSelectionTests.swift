import Foundation
@testable import Screenshot_Bro
import Testing

@MainActor
struct ShowcaseExportSelectionTests {
    private let first = ScreenshotRow(label: "A", templates: [ScreenshotTemplate(), ScreenshotTemplate()])
    private let second = ScreenshotRow(label: "B", templates: [ScreenshotTemplate()])
    private let third = ScreenshotRow(label: "C", templates: [ScreenshotTemplate(), ScreenshotTemplate()])

    private func selection(selected: [ScreenshotRow], excluding: Set<UUID> = []) -> ShowcaseExportSelection {
        ShowcaseExportSelection(
            candidateRows: [first, second, third],
            selectedRowIds: Set(selected.map(\.id)),
            excludedTemplateIds: excluding
        )
    }

    @Test func selectedRowsKeepCandidateOrderAndDropExcludedTemplates() {
        let rows = selection(selected: [third, first], excluding: [third.templates[0].id]).selectedRowsOrdered
        #expect(rows.map(\.id) == [first.id, third.id])
        #expect(rows[1].templates.map(\.id) == [third.templates[1].id])
    }

    @Test func aRowWithEveryTemplateExcludedIsDropped() {
        let current = selection(selected: [second], excluding: [second.templates[0].id])
        #expect(current.selectedRowsOrdered.isEmpty)
        #expect(current.sampleRow?.id == first.id)
    }

    @Test func sampleRowPrefersTheFirstSelectedRow() {
        #expect(selection(selected: [third, second]).sampleRow?.id == second.id)
    }

    @Test func noCandidatesHaveNoSampleRow() {
        let empty = ShowcaseExportSelection(candidateRows: [], selectedRowIds: [], excludedTemplateIds: [])
        #expect(empty.sampleRow == nil)
        #expect(empty.summary == .empty)
    }

    @Test func summaryCountsSelectedRows() {
        #expect(selection(selected: []).summary == .empty)
        #expect(selection(selected: [first, second, third]).summary == .all(3))
        #expect(selection(selected: [second]).summary == .partial(1, of: 3))
    }

    @Test func summaryLeavesOutRowsWithEveryScreenshotTurnedOff() {
        let allButSecond = selection(selected: [first, second, third], excluding: [second.templates[0].id])
        #expect(allButSecond.summary == .partial(2, of: 3))
        #expect(selection(selected: [second], excluding: [second.templates[0].id]).summary == .empty)
    }
}
