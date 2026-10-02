import SwiftUI

/// The plan step's per-language note on what the store already holds. Labels are shared; each
/// store words its own tooltips.
struct StoreRemoteScreenshotBadge: View {
    struct Tooltips {
        let empty: LocalizedStringResource
        let missingForThisType: LocalizedStringResource
        let present: LocalizedStringResource
        let presentLabel: (Int) -> LocalizedStringResource
    }

    let status: StoreRemoteScreenshotStatus?
    let tooltips: Tooltips

    var body: some View {
        if let status {
            switch status {
            case .empty:
                Label("No screenshots", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(Text(tooltips.empty))
            case .missingForThisType:
                Label("None in this size", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.orange)
                    .help(Text(tooltips.missingForThisType))
            case .present(let count):
                Text(tooltips.presentLabel(count))
                    .foregroundStyle(.secondary)
                    .help(Text(tooltips.present))
            }
        }
    }
}
