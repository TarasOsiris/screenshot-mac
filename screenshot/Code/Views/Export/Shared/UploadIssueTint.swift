import SwiftUI

extension UploadIssueSeverity {
    var tint: Color { self == .error ? .red : .orange }
}
