import SwiftUI

// AppState is the live document, so it is the production RowRenderSource. Declared here rather
// than on the protocol's file so Rendering/ keeps no dependency on App/.
extension AppState: RowRenderSource {}
