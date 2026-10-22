import SwiftUI

extension EnvironmentValues {
    /// The editor's `ReviewPromptScheduler`, which the upload wizards it presents report to.
    @Entry var reviewPrompt: ReviewPromptScheduler?
}

extension View {
    /// Counts a wizard closed on a finished upload as a review-prompt success moment.
    func reportsUploadSuccess(_ endedWithUpload: @escaping () -> Bool) -> some View {
        modifier(UploadSuccessReporter(endedWithUpload: endedWithUpload))
    }
}

private struct UploadSuccessReporter: ViewModifier {
    @Environment(\.reviewPrompt) private var reviewPrompt
    let endedWithUpload: () -> Bool

    func body(content: Content) -> some View {
        content.onDisappear {
            if endedWithUpload() { reviewPrompt?.recordSuccess(.upload) }
        }
    }
}
