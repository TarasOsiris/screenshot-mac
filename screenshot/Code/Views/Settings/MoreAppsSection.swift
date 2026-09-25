import SBAppPortfolio
import SBAppPortfolioCore
import SwiftUI

/// The developer's other App Store apps, listed in Settings ▸ About on both platforms.
struct MoreAppsSection: View {
    /// macOS keeps every settings pane mounted, so the lookup waits until About is actually shown.
    var isVisible = true

    @State private var items = Self.catalog.map { SBAppPortfolioItem(reference: $0) }

    private static let developerPageURL = URL(string: "https://apps.apple.com/developer/id955984247")!

    private static let catalog = [
        SBAppReference(
            appID: "6770987720",
            fallbackName: "Captions Bro",
            fallbackDescription: String(localized: "Auto subtitles for your videos.")
        ),
        SBAppReference(
            appID: "6759321248",
            fallbackName: "Recurring Tasks & Routines",
            fallbackDescription: String(localized: "Build routines that repeat on your schedule.")
        ),
        SBAppReference(
            appID: "6758044383",
            fallbackName: "Table Tennis Training Tracker",
            fallbackDescription: String(localized: "Log and track your table tennis practice.")
        ),
    ]

    var body: some View {
        Section("More Apps") {
            ForEach(items) { item in
                SBAppPortfolioRowView(item: item, showsGenre: false)
                    // Overrides the package's own row fill so rows match the host Form's sections.
                    .listRowBackground(Color?.none)
            }
            Link(destination: Self.developerPageURL) {
                Label("View All Apps on the App Store", systemImage: "square.grid.2x2")
            }
        }
        .task(id: isVisible) {
            guard isVisible else { return }
            await loadStoreMetadata()
        }
    }

    private func loadStoreMetadata() async {
        let request = SBAppLookupRequest(
            appIDs: Self.catalog.map(\.appID),
            countryCode: Locale.current.region?.identifier ?? "us"
        )
        guard let result = try? await SBAppStoreLookupService().fetchApps(for: request) else { return }
        items = Self.catalog.map { SBAppPortfolioItem(reference: $0, storeApp: result.app(forAppID: $0.appID)) }
    }
}
