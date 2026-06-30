import SwiftUI

struct ASCPlatformBadge: View {
    enum Style {
        case capsule
        case iconOnly
    }

    let platform: ASCPlatform?
    let fallbackName: String?
    var style: Style = .capsule

    init(platform: ASCPlatform?, fallbackName: String? = nil, style: Style = .capsule) {
        self.platform = platform
        self.fallbackName = fallbackName
        self.style = style
    }

    var body: some View {
        if let descriptor {
            switch style {
            case .capsule:
                Label {
                    Text(verbatim: descriptor.title)
                } icon: {
                    Image(systemName: descriptor.systemImageName)
                }
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15), in: .capsule)
                .accessibilityLabel(Text(verbatim: descriptor.title))
            case .iconOnly:
                Image(systemName: descriptor.systemImageName)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .help(descriptor.title)
                    .accessibilityHidden(true)
            }
        }
    }

    private var descriptor: PlatformDescriptor? {
        if let platform {
            return PlatformDescriptor(
                title: platform.displayName,
                systemImageName: platform.uploadFlowSystemImageName
            )
        }

        guard let fallbackName, !fallbackName.isEmpty else { return nil }
        return PlatformDescriptor(title: fallbackName, systemImageName: "app")
    }
}

private struct PlatformDescriptor {
    let title: String
    let systemImageName: String
}

private extension ASCPlatform {
    var uploadFlowSystemImageName: String {
        switch self {
        case .ios:
            "iphone"
        case .macOS:
            "desktopcomputer"
        case .tvOS:
            "tv"
        case .visionOS:
            "viewfinder"
        }
    }
}
