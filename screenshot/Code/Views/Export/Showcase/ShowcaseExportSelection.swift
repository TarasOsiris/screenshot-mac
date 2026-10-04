import Foundation

/// Which rows and screenshots the showcase export covers, derived from the sheet's selection state.
struct ShowcaseExportSelection {
    enum Summary: Equatable {
        case empty
        case all(Int)
        case partial(Int, of: Int)
    }

    let candidateRows: [ScreenshotRow]
    /// Rows whose screenshots are all excluded drop out: they would render empty.
    let selectedRowsOrdered: [ScreenshotRow]

    init(candidateRows: [ScreenshotRow], selectedRowIds: Set<UUID>, excludedTemplateIds: Set<UUID>) {
        self.candidateRows = candidateRows
        selectedRowsOrdered = candidateRows
            .filter { selectedRowIds.contains($0.id) }
            .compactMap { $0.filtering(excluding: excludedTemplateIds) }
    }

    var sampleRow: ScreenshotRow? {
        selectedRowsOrdered.first ?? candidateRows.first
    }

    var summary: Summary {
        // Counts what will export, so a row with every screenshot turned off isn't announced.
        let count = selectedRowsOrdered.count
        if count == 0 { return .empty }
        if count == candidateRows.count { return .all(count) }
        return .partial(count, of: candidateRows.count)
    }
}
