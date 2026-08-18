import SwiftUI

// SwiftUI bindings for the flow model. Kept in Views/ so Services/ declares no SwiftUI.
extension ASCUploadFlowModel {
    /// The plan screen edits destinations in place through a `ForEach($binding)`. Routing that
    /// through `updateDestinationPlans` is what keeps `planEntries` from going stale — an
    /// ordinary `@Bindable` write would bypass the setter and leave the memo behind.
    var destinationPlansBinding: Binding<[ASCDestinationPlan]> {
        Binding(
            get: { self.destinationPlans },
            set: { self.updateDestinationPlans($0) }
        )
    }
}
