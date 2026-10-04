#if os(macOS)
import Foundation

extension MCPToolExecutor {
    struct ASCScreenshotPreviewResult: Encodable {
        let planId: String
        /// Echoed so a caller can assert which project the plan was built from rather than
        /// trusting that the app happened to have the right one open.
        let projectId: String
        let projectName: String
        let appId: String
        let expiresAt: String
        let issues: [String]
        let sets: [SetResult]

        struct SetResult: Encodable {
            let setId: String
            let remoteSetId: String?
            let versionId: String
            let version: String
            let locale: String
            let displayType: String
            let status: String
            let canApply: Bool
            let unchanged: Int
            let moved: Int
            let new: Int
            let removed: Int
            let capacityFirstDeletions: Int
            let issues: [String]
            /// Non-blocking notices — most usefully "these have no App Store checksum, so they
            /// will be replaced rather than preserved", i.e. a preserve that is really a replace.
            let warnings: [String]
        }
    }

    struct ASCScreenshotApplyResult: Encodable {
        let planId: String
        let succeeded: Bool
        /// Whether anything was written to the live listing. The single most useful bit on a
        /// partial failure, and previously invisible to an agent.
        let didMutate: Bool
        let attempted: Int
        let alreadyApplied: Int
        let sets: [SetResult]

        struct SetResult: Encodable {
            let setId: String
            let state: String
            let uploaded: Int
            let removed: Int
            let moved: Int
            let preserved: Int
            let finalVerified: Bool
            let assetDeliveryStates: [String: Int]
            let nonCompleteAssets: [ASCScreenshotDeliveryProblem]
            let warnings: [String]
            let error: String?
        }
    }

    struct ASCMetadataResult: Encodable {
        let appId: String
        let versions: [VersionMeta]

        struct VersionMeta: Encodable {
            let versionId: String
            let platform: String?
            let versionString: String
            let appStoreState: String?
            let editable: Bool
            let locales: [LocaleDescription]
        }

        struct LocaleDescription: Encodable {
            let locale: String
            let description: String?
        }
    }

    struct ASCDescriptionUpdateResult: Encodable {
        let appId: String
        let results: [VersionResult]

        struct VersionResult: Encodable {
            let versionId: String
            let platform: String?
            let updated: [String]
            let skipped: [Skip]
        }

        struct Skip: Encodable {
            let locale: String
            let reason: String
        }
    }
}
#endif
