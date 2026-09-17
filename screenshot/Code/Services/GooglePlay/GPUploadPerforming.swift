import Foundation

/// The one call the Google Play upload flow makes, behind a protocol so the flow's
/// success / cancellation / failure branches can be tested without the network.
///
/// Takes `any RowRenderSource`, not `some`: a protocol requirement can't be generic over it, and
/// an overload pair differing only that way would resolve back to itself. The service's own
/// parameter is `any` for the same reason — `source` is only handed to `RowRenderContext`, which
/// opens the existential implicitly.
@MainActor
protocol GPUploadPerforming {
    @discardableResult
    func upload(
        packageName: String,
        targets: [GPUploadTarget],
        sendForReview: Bool,
        rows: [ScreenshotRow],
        source: any RowRenderSource,
        progress: @escaping (UploadProgress) -> Void
    ) async throws -> Bool
}

extension GooglePlayUploadService: GPUploadPerforming {}

/// The package-name check the wizard runs before building a plan, behind its own protocol for the
/// same reason: the flow's verified / rejected branches should test without opening a real edit.
@MainActor
protocol GPPackageVerifying {
    func verifyPackage(packageName: String) async throws
}

extension GooglePlayAPIService: GPPackageVerifying {}
