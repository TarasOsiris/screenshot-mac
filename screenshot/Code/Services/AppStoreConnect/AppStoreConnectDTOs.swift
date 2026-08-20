import Foundation

// The wire shapes of the App Store Connect API, split out of `AppStoreConnectAPIService` so the
// client itself is about requests rather than 380 lines of Decodable.

nonisolated struct ASCListResponse<T: Decodable>: Decodable {
    let data: [T]
}

nonisolated struct ASCSingleResponse<T: Decodable>: Decodable {
    let data: T
}

nonisolated struct ASCAppWithVersions {
    let app: ASCApp
    let versions: [ASCAppStoreVersion]

    var hasScreenshotUploadableVersion: Bool { versions.contains(where: \.isScreenshotUploadable) }
}

nonisolated struct ASCAppListWithVersionsResponse: Decodable {
    let data: [AppRow]
    let included: [IncludedItem]?

    struct AppRow: Decodable {
        let id: String
        let attributes: ASCApp.Attributes
        let relationships: Relationships?

        struct Relationships: Decodable {
            let appStoreVersions: VersionLinks?
        }

        struct VersionLinks: Decodable {
            let data: [Reference]?
        }

        struct Reference: Decodable {
            let id: String
            let type: String
        }
    }

    struct IncludedItem: Decodable {
        let id: String
        let type: String
        let attributes: ASCAppStoreVersion.Attributes?
    }
}

nonisolated struct ASCApp: Decodable, Identifiable {
    let id: String
    let attributes: Attributes

    struct Attributes: Decodable {
        let name: String
        let bundleId: String
        let sku: String?
        let primaryLocale: String?
    }
}

nonisolated enum ASCPlatform: String, CaseIterable {
    case ios = "IOS"
    case macOS = "MAC_OS"
    case tvOS = "TV_OS"
    case visionOS = "VISION_OS"

    var displayName: String {
        switch self {
        case .ios: return "iOS"
        case .macOS: return "macOS"
        case .tvOS: return "tvOS"
        case .visionOS: return "visionOS"
        }
    }
}

nonisolated struct ASCAppStoreVersion: Decodable, Identifiable {
    let id: String
    let attributes: Attributes

    struct Attributes: Decodable {
        let versionString: String
        let appStoreState: String?
        let platform: String?
        let copyright: String?

        init(
            versionString: String,
            appStoreState: String?,
            platform: String?,
            copyright: String? = nil
        ) {
            self.versionString = versionString
            self.appStoreState = appStoreState
            self.platform = platform
            self.copyright = copyright
        }

        var displayState: String {
            guard let raw = appStoreState, !raw.isEmpty else { return String(localized: "not editable") }
            return raw.replacing("_", with: " ").lowercased()
        }

        var ascPlatform: ASCPlatform? {
            guard let platform, !platform.isEmpty else { return nil }
            return ASCPlatform(rawValue: platform)
        }

        var displayPlatform: String? {
            if let ascPlatform { return ascPlatform.displayName }
            guard let platform, !platform.isEmpty else { return nil }
            return platform.replacing("_", with: " ").capitalized
        }
    }

    var isEditable: Bool {
        switch attributes.appStoreState {
        case "PREPARE_FOR_SUBMISSION",
             "DEVELOPER_REJECTED",
             "REJECTED",
             "METADATA_REJECTED",
             "INVALID_BINARY",
             "WAITING_FOR_REVIEW",
             "IN_REVIEW":
            return true
        default:
            return false
        }
    }

    var isScreenshotUploadable: Bool {
        guard let state = attributes.appStoreState else { return false }
        return Self.screenshotUploadableStates.contains(state)
    }

    private static let screenshotUploadableStates: Set<String> = [
        "PREPARE_FOR_SUBMISSION",
        "DEVELOPER_REJECTED",
        "REJECTED",
        "METADATA_REJECTED",
        "INVALID_BINARY"
    ]
}

nonisolated struct ASCAppStoreVersionLocalization: Decodable, Identifiable {
    let id: String
    let attributes: Attributes

    struct Attributes: Decodable {
        let locale: String
        let description: String?
        let keywords: String?
        let promotionalText: String?
        let whatsNew: String?
        let marketingUrl: String?
        let supportUrl: String?

        init(
            locale: String,
            description: String? = nil,
            keywords: String? = nil,
            promotionalText: String? = nil,
            whatsNew: String? = nil,
            marketingUrl: String? = nil,
            supportUrl: String? = nil
        ) {
            self.locale = locale
            self.description = description
            self.keywords = keywords
            self.promotionalText = promotionalText
            self.whatsNew = whatsNew
            self.marketingUrl = marketingUrl
            self.supportUrl = supportUrl
        }
    }
}

nonisolated struct ASCAppInfo: Decodable, Identifiable {
    let id: String
    let attributes: Attributes?

    struct Attributes: Decodable {
        let state: String?
        let appStoreState: String?

        init(state: String? = nil, appStoreState: String? = nil) {
            self.state = state
            self.appStoreState = appStoreState
        }
    }

    var effectiveState: String? {
        attributes?.state ?? attributes?.appStoreState
    }

    var isEditable: Bool {
        guard let state = effectiveState else { return false }
        return Self.editableStates.contains(state)
    }

    private static let editableStates: Set<String> = [
        "PREPARE_FOR_SUBMISSION",
        "DEVELOPER_REJECTED",
        "REJECTED",
        "METADATA_REJECTED",
        "WAITING_FOR_REVIEW",
        "IN_REVIEW"
    ]
}

nonisolated struct ASCAppInfoLocalization: Decodable, Identifiable {
    let id: String
    let attributes: Attributes

    struct Attributes: Decodable {
        let locale: String
        let name: String?
        let subtitle: String?
        let privacyPolicyUrl: String?
        let privacyPolicyText: String?
        let privacyChoicesUrl: String?

        init(
            locale: String,
            name: String? = nil,
            subtitle: String? = nil,
            privacyPolicyUrl: String? = nil,
            privacyPolicyText: String? = nil,
            privacyChoicesUrl: String? = nil
        ) {
            self.locale = locale
            self.name = name
            self.subtitle = subtitle
            self.privacyPolicyUrl = privacyPolicyUrl
            self.privacyPolicyText = privacyPolicyText
            self.privacyChoicesUrl = privacyChoicesUrl
        }
    }
}

nonisolated struct ASCAppScreenshotSet: Decodable, Identifiable {
    let id: String
    let attributes: Attributes

    struct Attributes: Decodable {
        let screenshotDisplayType: String?
    }
}

nonisolated struct ASCAppScreenshot: Decodable, Identifiable {
    let id: String
    let attributes: Attributes

    struct Attributes: Decodable {
        let fileName: String?
        let fileSize: Int?
        let uploaded: Bool?
        let sourceFileChecksum: String?
        let uploadOperations: [ASCUploadOperation]?
        let imageAsset: ASCImageAsset?
        let assetToken: String?
        let assetType: String?
        let assetDeliveryState: ASCAssetDeliveryState?

        init(
            fileName: String? = nil,
            fileSize: Int? = nil,
            uploaded: Bool? = nil,
            sourceFileChecksum: String? = nil,
            uploadOperations: [ASCUploadOperation]? = nil,
            imageAsset: ASCImageAsset? = nil,
            assetToken: String? = nil,
            assetType: String? = nil,
            assetDeliveryState: ASCAssetDeliveryState? = nil
        ) {
            self.fileName = fileName
            self.fileSize = fileSize
            self.uploaded = uploaded
            self.sourceFileChecksum = sourceFileChecksum
            self.uploadOperations = uploadOperations
            self.imageAsset = imageAsset
            self.assetToken = assetToken
            self.assetType = assetType
            self.assetDeliveryState = assetDeliveryState
        }
    }
}

nonisolated struct ASCImageAsset: Decodable, Sendable {
    let templateUrl: String
    let width: Int
    let height: Int
}

nonisolated struct ASCAssetDeliveryState: Decodable, Sendable {
    let state: String?
    let errors: [ASCAssetDeliveryError]?
    let warnings: [ASCAssetDeliveryError]?

    var isComplete: Bool { state?.uppercased() == "COMPLETE" }
    var isFailed: Bool { state?.uppercased() == "FAILED" }
}

nonisolated struct ASCAssetDeliveryError: Decodable, Sendable {
    let code: String?
    let message: String?
}

nonisolated struct ASCUploadOperation: Decodable {
    let method: String
    let url: String
    let length: Int
    let offset: Int
    let requestHeaders: [ASCUploadHeader]
}

nonisolated struct ASCUploadHeader: Decodable {
    let name: String
    let value: String
}
