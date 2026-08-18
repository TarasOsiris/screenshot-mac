#if os(macOS)
import AppKit
#endif
import SwiftUI

// The alert presentation for `TranslationLanguageIssue`. The issue itself is a service-layer
// value (Services/Localization/TranslationService.swift); only its presentation lives here, so
// `Services/` declares no `some View`.
extension View {
    func translationLanguageIssueAlert(item: Binding<TranslationLanguageIssue?>) -> some View {
        return alert(
            item.wrappedValue?.title ?? "",
            isPresented: item.isPresent(),
            presenting: item.wrappedValue
        ) { issue in
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
