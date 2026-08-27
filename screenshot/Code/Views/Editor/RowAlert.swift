import SwiftUI

/// The alerts a row can raise. One case per outcome so `EditorRowView` carries a single
/// presentation modifier rather than one per outcome — it is instantiated per row inside
/// ContentView's `LazyVStack`, so every extra modifier is multiplied by the row count.
enum RowAlert {
    case deleteRow
    case resetRow
    case exportFailed(String)
    case backgroundRemovalFailed(String)
    #if DEBUG
    case simulatorCaptureFailed(String)
    #endif
    #if DEBUG && os(macOS)
    case simulatorInstallPrompt(shapeId: UUID)
    #endif

    var title: LocalizedStringKey {
        switch self {
        case .deleteRow: "Delete Row"
        case .resetRow: "Reset Row"
        case .exportFailed: "Export Failed"
        case .backgroundRemovalFailed: "Remove Background Failed"
        #if DEBUG
        case .simulatorCaptureFailed: "iOS Simulator Capture Failed"
        #endif
        #if DEBUG && os(macOS)
        case .simulatorInstallPrompt: "Enable iOS Simulator Capture"
        #endif
        }
    }
}
