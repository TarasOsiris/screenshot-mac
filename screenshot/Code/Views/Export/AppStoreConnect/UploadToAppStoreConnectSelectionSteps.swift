import SwiftUI

struct ASCAppSelectionStepView: View {
    var mode: ASCFlowMode = .screenshots
    let appsWithVersions: [ASCAppWithVersions]

    @Binding var selectedApp: ASCApp?
    @Binding var hideNonUploadable: Bool

    private var apps: [ASCApp] {
        appsWithVersions.map(\.app)
    }

    private var visibleAppsWithVersions: [ASCAppWithVersions] {
        hideNonUploadable
            ? appsWithVersions.filter { $0.hasSelectableVersion(for: mode) }
            : appsWithVersions
    }

    private var hiddenAppCount: Int {
        appsWithVersions.count { !$0.hasSelectableVersion(for: mode) }
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
                if mode == .metadata {
                    if hiddenAppCount > 0 {
                        Text("Hide non-editable (\(hiddenAppCount))")
                    } else {
                        Text("Hide non-editable")
                    }
                } else if hiddenAppCount > 0 {
                    Text("Hide non-uploadable (\(hiddenAppCount))")
                } else {
                    Text("Hide non-uploadable")
                }
            }
            .toggleStyle(.switch)
            .compactControlSize()
            .help(mode == .metadata
                  ? String(localized: "Hide apps with no editable App Store version. Apps that are already live can't accept metadata changes until you create a new version.")
                  : String(localized: "Hide apps with no editable App Store version. Apps in review or already live can't accept new screenshots until you create a new version."))
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
            set: { id in
                selectedApp = apps.first { $0.id == id }
            }
        )) {
            ForEach(visibleAppsWithVersions, id: \.app.id) { item in
                ASCAppHeaderView(app: item.app, subtitle: item.app.attributes.bundleId, iconSize: 36)
                    .tag(item.app.id as String?)
            }
        }
        .ascSelectionListStyle()
    }

}

struct ASCVersionSelectionStepView: View {
    var mode: ASCFlowMode = .screenshots
    let selectedApp: ASCApp?
    let versions: [ASCAppStoreVersion]

    @Binding var selectedVersionIds: Set<String>
    @State private var showReadOnlyVersions = false

    private var hasSelectableVersion: Bool {
        versions.contains { $0.isSelectable(for: mode) }
    }

    private var readOnlyVersionCount: Int {
        versions.count { !$0.isSelectable(for: mode) }
    }

    private var visibleVersions: [ASCAppStoreVersion] {
        showReadOnlyVersions ? versions : versions.filter { $0.isSelectable(for: mode) }
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
            if !versions.isEmpty && !hasSelectableVersion {
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
                .help(mode == .metadata
                      ? String(localized: "Show versions that are already live. Metadata can only be changed on editable versions.")
                      : String(localized: "Show versions that are locked for review or live. Screenshots can only be uploaded to editable versions."))
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
            Text(mode == .metadata
                 ? "Every version on this app is already live. Create a new version in App Store Connect, then refresh this wizard."
                 : "Every version on this app is locked for review or live. Create a new version in App Store Connect, then refresh this wizard.")
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
                            ASCVersionSelectionRow(version: version, mode: mode)
                        }
                        #if os(macOS)
                        .toggleStyle(.checkbox)
                        #else
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        #endif
                        .disabled(!version.isSelectable(for: mode))
                    }
                }
            }
        }
        .ascSelectionListStyle()
    }

    @ViewBuilder
    private var selectedReadOnlyVersionWarning: some View {
        let selectedReadOnlyVersions = versions.filter { selectedVersionIds.contains($0.id) && !$0.isSelectable(for: mode) }
        if let selectedVersion = selectedReadOnlyVersions.first {
            Label(mode == .metadata
                  ? "Version \(selectedVersion.attributes.versionString) is \(selectedVersion.attributes.displayState) — metadata can't be changed. Pick an editable version or create a new one in App Store Connect."
                  : "Version \(selectedVersion.attributes.versionString) is \(selectedVersion.attributes.displayState) — screenshots can't be changed. Pick an editable version or create a new one in App Store Connect.",
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
    let mode: ASCFlowMode

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
            if !version.isSelectable(for: mode) {
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
