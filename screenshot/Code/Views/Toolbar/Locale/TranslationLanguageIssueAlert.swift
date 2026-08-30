#if os(macOS)
import AppKit
#endif
import SwiftUI

// The alert presentation for `TranslationLanguageIssue`. The issue itself is a service-layer
// value (Services/Localization/TranslationService.swift); only its presentation lives here, so
// `Services/` declares no `some View`.
extension View {
    /// `onRetry` re-runs the translation that produced the issue. It is the primary action for
    /// every recoverable case: `prepareTranslation()` is what presents Apple's download sheet, so
    /// retrying brings the sheet back — a user who dismissed it once had to restart the whole run
    /// by hand before this existed.
    func translationLanguageIssueAlert(
        item: Binding<TranslationLanguageIssue?>,
        onRetry: @escaping () -> Void
    ) -> some View {
        return alert(
            item.wrappedValue?.title ?? "",
            isPresented: item.isPresent(),
            presenting: item.wrappedValue
        ) { issue in
            if issue.offersRetry {
                Button("Try Again") { onRetry() }
            }
            #if os(macOS)
            if issue.offersSettings, let url = URL(string: "x-apple.systempreferences:com.apple.SystemPreferences.TranslationSettings") {
                Button("Open Translation Settings") {
                    NSWorkspace.shared.open(url)
                }
            }
            #endif
            Button("OK", role: .cancel) {}
        } message: { issue in
            Text(issue.message)
        }
    }
}
