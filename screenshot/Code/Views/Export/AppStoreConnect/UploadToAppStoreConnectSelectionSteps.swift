import SwiftUI

struct ASCAppSelectionStepView: View {
    let appsWithVersions: [ASCAppWithVersions]

    @Binding var selectedApp: ASCApp?
    @Binding var hideNonUploadable: Bool

    private var apps: [ASCApp] {
        appsWithVersions.map(\.app)
    }

    private var visibleAppsWithVersions: [ASCAppWithVersions] {
        hideNonUploadable
            ? appsWithVersions.filter(\.hasScreenshotUploadableVersion)
            : appsWithVersions
    }

    private var nonUploadableAppCount: Int {
        appsWithVersions.filter { !$0.hasScreenshotUploadableVersion }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if visibleAppsWithVersions.isEmpty && !appsWithVersions.isEmpty {
                hiddenAppsEmptyState
            } else {
                appList
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Select an app")
                .font(.headline)
            Spacer()
            Toggle(isOn: $hideNonUploadable) {
                if nonUploadableAppCount > 0 {
                    Text("Hide non-uploadable (\(nonUploadableAppCount))")
                } else {
                    Text("Hide non-uploadable")
                }
            }
            .toggleStyle(.switch)
            .compactControlSize()
            .help("Hide apps with no editable App Store version. Apps in review or already live can't accept new screenshots until you create a new version.")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var hiddenAppsEmptyState: some View {
        VStack(spacing: 6) {
            Label("All apps are hidden by the filter", systemImage: "line.3.horizontal.decrease.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("None of your apps have an editable version right now. Turn off the filter to see them all.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 16)
    }

    private var appList: some View {
        List(selection: Binding(
            get: { selectedApp?.id },
            set: selectApp
        )) {
            ForEach(visibleAppsWithVersions, id: \.app.id) { item in
                ASCAppHeaderView(app: item.app, subtitle: item.app.attributes.bundleId, iconSize: 36)
                    .tag(item.app.id as String?)
            }
        }
        .ascSelectionListStyle()
    }

    private func selectApp(id: String?) {
        selectedApp = apps.first { $0.id == id }
    }
}

struct ASCVersionSelectionStepView: View {
    let selectedApp: ASCApp?
    let versions: [ASCAppStoreVersion]

    @Binding var selectedVersionIds: Set<String>
    @State private var showReadOnlyVersions = false

    private var hasUploadableVersion: Bool {
        versions.contains(where: \.isScreenshotUploadable)
    }

    private var readOnlyVersionCount: Int {
        versions.filter { !$0.isScreenshotUploadable }.count
    }

    private var visibleVersions: [ASCAppStoreVersion] {
        showReadOnlyVersions ? versions : versions.filter(\.isScreenshotUploadable)
    }

    private var versionGroups: [(String, [ASCAppStoreVersion])] {
        let grouped = Dictionary(grouping: visibleVersions) { version in
            version.attributes.displayPlatform ?? String(localized: "Other")
        }
        return grouped.keys.sorted().map { key in
            (key, grouped[key] ?? [])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            title
            appHeader
            if !versions.isEmpty && !hasUploadableVersion {
                noEditableVersionCallout
            }
            versionList
            selectedReadOnlyVersionWarning
        }
    }

    private var title: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Select versions")
                .font(.headline)
            Spacer()
            if readOnlyVersionCount > 0 {
                Toggle(isOn: $showReadOnlyVersions) {
                    Text("Show read-only (\(readOnlyVersionCount))")
                }
                .toggleStyle(.switch)
                .compactControlSize()
                .help("Show versions that are locked for review or live. Screenshots can only be uploaded to editable versions.")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var appHeader: some View {
        if let selectedApp {
            ASCAppHeaderView(app: selectedApp, subtitle: selectedApp.attributes.bundleId)
                .padding(.horizontal, 16)
        }
    }

    private var noEditableVersionCallout: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("No editable version available", systemImage: "lock.fill")
                .foregroundStyle(.orange)
                .font(.callout)
                .fontWeight(.medium)
            Text("Every version on this app is locked for review or live. Create a new version in App Store Connect, then refresh this wizard.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            appStoreConnectLink
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: .rect(cornerRadius: 8))
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var appStoreConnectLink: some View {
        if let selectedApp,
           let url = URL(string: "https://appstoreconnect.apple.com/apps/\(selectedApp.id)/appstore") {
            Link(destination: url) {
                Label("Open app in App Store Connect", systemImage: "arrow.up.right.square")
            }
            .font(.caption)
        }
    }

    private var versionList: some View {
        List {
            ForEach(versionGroups, id: \.0) { group in
                Section(group.0) {
                    ForEach(group.1) { version in
                        Toggle(isOn: $selectedVersionIds.contains(version.id)) {
                            ASCVersionSelectionRow(version: version)
                        }
                        #if os(macOS)
                        .toggleStyle(.checkbox)
                        #else
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        #endif
                        .disabled(!version.isScreenshotUploadable)
                    }
                }
            }
        }
        .ascSelectionListStyle()
    }

    @ViewBuilder
    private var selectedReadOnlyVersionWarning: some View {
        let selectedReadOnlyVersions = versions.filter { selectedVersionIds.contains($0.id) && !$0.isScreenshotUploadable }
        if let selectedVersion = selectedReadOnlyVersions.first {
            Label("Version \(selectedVersion.attributes.versionString) is \(selectedVersion.attributes.displayState) — screenshots can't be changed. Pick an editable version or create a new one in App Store Connect.",
                  systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
        }
    }
}

private struct ASCVersionSelectionRow: View {
    let version: ASCAppStoreVersion

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(version.attributes.versionString)
                        .fontWeight(.medium)
                    platformBadge
                }
                Text(version.attributes.displayState)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !version.isScreenshotUploadable {
                Label("Read-only", systemImage: "lock.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
        }
    }

    @ViewBuilder
    private var platformBadge: some View {
        ASCPlatformBadge(
            platform: version.attributes.ascPlatform,
            fallbackName: version.attributes.displayPlatform
        )
    }
}

private extension View {
    /// Desktop inset list on macOS; grouped inset on iPad for a native selection look.
    @ViewBuilder
    func ascSelectionListStyle() -> some View {
        #if os(macOS)
        listStyle(.inset)
        #else
        listStyle(.insetGrouped)
        #endif
    }
}
