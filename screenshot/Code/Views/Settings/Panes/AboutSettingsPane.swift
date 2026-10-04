import SwiftUI

#if os(macOS)
struct AboutSettingsPane: View {
    /// Settings keeps every pane mounted, so the pane can't tell from `onAppear` whether it shows.
    let isVisible: Bool

    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: UIMetrics.About.appIconSize, height: UIMetrics.About.appIconSize)
                        .accessibilityHidden(true)
                    Text(verbatim: "Screenshot Bro")
                        .font(.title2.weight(.semibold))
                    Text("Version \(Bundle.main.shortVersion) (\(Bundle.main.buildNumber))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text(DistributionChannel.current.displayName)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    SocialLinkButtons()
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            #if DIRECT_DISTRIBUTION
            DirectUpdateSettingsSection()
            #endif

            Section {
                AboutLinkRows()
            }

            MoreAppsSection(isVisible: isVisible)
        }
        .formStyle(.grouped)
    }
}
#endif
