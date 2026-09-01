import SwiftUI

// AppState is the live document, so it is the production RowRenderSource, ExportDocument and
// store-upload document. Declared here rather than on the protocols' files so Rendering/ and
// Services/ keep no dependency on App/.
extension AppState: RowRenderSource {}

extension AppState: ExportDocument {
    var activeProjectName: String { activeProject?.name ?? "" }

    func commitPendingEdits() { commitAllPendingEdits() }
}

extension AppState: StoreUploadDocument {}

extension AppState: ASCUploadDocument {
    var savedASCAppId: String? { activeProject?.ascAppId }

    func rememberASCAppId(_ appId: String) {
        guard let projectId = activeProject?.id else { return }
        setASCAppId(appId, forProject: projectId)
    }
}

extension AppState: GPUploadDocument {
    var savedGooglePlayPackageName: String? { activeProject?.googlePlayPackageName }

    func rememberGooglePlayPackageName(_ packageName: String?) {
        guard let projectId = activeProject?.id else { return }
        setGooglePlayPackageName(packageName, forProject: projectId)
    }
}
