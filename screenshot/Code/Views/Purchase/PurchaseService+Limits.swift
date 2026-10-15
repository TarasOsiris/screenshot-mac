import SwiftUI

extension PurchaseService {
    /// Runs a template-adding action behind the free tier's template limit.
    func addTemplateIfAllowed(currentCount: Int, _ action: () -> Void) {
        requirePro(allowed: canAddTemplate(currentCount: currentCount), context: .templateLimit) {
            withAnimation(.easeInOut(duration: 0.2)) { action() }
        }
    }

    /// Runs a row-adding action behind the free tier's row limit.
    func addRowIfAllowed(currentCount: Int, _ action: () -> Void) {
        requirePro(allowed: canAddRow(currentCount: currentCount), context: .rowLimit) {
            withAnimation(.easeInOut(duration: 0.2)) { action() }
        }
    }

    /// Runs a project-creating action behind the free tier's project limit.
    func createProjectIfAllowed(currentCount: Int, _ action: () -> Void) {
        requirePro(allowed: canCreateProject(currentCount: currentCount), context: .projectLimit, action: action)
    }
}
