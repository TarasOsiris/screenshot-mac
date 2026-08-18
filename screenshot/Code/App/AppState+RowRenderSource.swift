import SwiftUI

// AppState is the live document, so it is the production RowRenderSource and ExportDocument.
// Declared here rather than on the protocols' files so Rendering/ and Services/ keep no
// dependency on App/.
extension AppState: RowRenderSource {}

extension AppState: ExportDocument {
    var activeProjectName: String { activeProject?.name ?? "" }
}
