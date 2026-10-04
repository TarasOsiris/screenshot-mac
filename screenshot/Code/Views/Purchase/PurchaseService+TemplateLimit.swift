import SwiftUI

extension PurchaseService {
    /// Runs a template-adding action behind the free tier's template limit.
    func addTemplateIfAllowed(currentCount: Int, _ action: () -> Void) {
        requirePro(allowed: canAddTemplate(currentCount: currentCount), context: .templateLimit) {
            withAnimation(.easeInOut(duration: 0.2)) { action() }
        }
    }
}
