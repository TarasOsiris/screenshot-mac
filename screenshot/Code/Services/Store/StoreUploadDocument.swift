import Foundation

/// What a store upload flow needs from the open document, beyond what rendering already needs.
/// `ExportDocument` covers `rows` + `activeProjectName` and, through `RowRenderSource`, everything
/// the renderers read — so an upload flow can run against a fixture instead of a live `AppState`.
@MainActor
protocol StoreUploadDocument: ExportDocument {
    /// Identifies the document revision an upload was planned against, so a plan built before an
    /// edit can be recognised as stale.
    var documentStamp: DocumentStamp? { get }
}
