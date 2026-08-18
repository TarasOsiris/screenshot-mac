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
