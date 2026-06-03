import SwiftUI

#if os(iOS)
/// iPad sheet chrome: a `NavigationStack` with an inline title and native toolbar
/// Done/Cancel actions. macOS keeps its own popover/window chrome, so this type is
/// iOS-only and `iosSheetChrome` is a no-op there. Titles are `Text` so callers can pass
/// either a localized literal (`Text("Done")`) or a runtime string (`Text(verbatim:)`).
private struct IOSSheetChrome<Content: View>: View {
    let title: Text
    let confirmTitle: Text
    let confirmDisabled: Bool
    let showsCancel: Bool
    let onConfirm: (() -> Void)?
    let onCancel: (() -> Void)?
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if showsCancel {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(role: .cancel) { onCancel?(); dismiss() } label: { Text("Cancel") }
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        // Prominent checkmark confirm. The confirm action owns dismissal: a
                        // bare "Done" dismisses, but a supplied onConfirm decides (e.g.
                        // SvgPasteDialog stays open and shows an error when validation fails).
                        // confirmTitle becomes the accessibility label for the icon.
                        Button {
                            if let onConfirm { onConfirm() } else { dismiss() }
                        } label: {
                            // Pin font + control size so the icon is identical regardless of
                            // the controlSize/font the presenting bar leaks into the sheet.
                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .disabled(confirmDisabled)
                        .accessibilityLabel(confirmTitle)
                    }
                }
        }
        // Detents (not `.presentationSizing(.fitted)`) give the sheet a real height — a
        // NavigationStack has no finite ideal size, so `.fitted` collapses it to just the
        // nav bar. `.fullScreenCover` (showcase export) ignores these, which is fine.
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
#endif

extension View {
    /// On iPad, wraps a sheet's content in a native navigation bar with a trailing
    /// confirm action (and optional leading Cancel). No-op on macOS, where modals keep
    /// their desktop chrome. Dismissal goes through the environment `\.dismiss`, so this
    /// works for both `isPresented:` and `item:` sheets.
    @ViewBuilder
    func iosSheetChrome(
        _ title: Text,
        confirmTitle: Text = Text("Done"),
        confirmDisabled: Bool = false,
        showsCancel: Bool = false,
        onConfirm: (() -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) -> some View {
        #if os(iOS)
        IOSSheetChrome(
            title: title,
            confirmTitle: confirmTitle,
            confirmDisabled: confirmDisabled,
            showsCancel: showsCancel,
            onConfirm: onConfirm,
            onCancel: onCancel
        ) { self }
        #else
        self
        #endif
    }

    /// A popover anchored to a control in the bottom properties bar.
    ///
    /// macOS shows a real popover above the anchor (`arrowEdge: .top`). On iPad a popover
    /// anchored to a control sitting at the very bottom of the screen renders partly
    /// off-screen, so present a detent-sized sheet instead with a native nav bar + Done
    /// button (`iosSheetChrome`) that's always fully on-screen.
    @ViewBuilder
    func barPopover<Content: View>(
        isPresented: Binding<Bool>,
        title: LocalizedStringKey,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        #if os(macOS)
        popover(isPresented: isPresented, arrowEdge: .top, content: content)
        #else
        sheet(isPresented: isPresented) {
            content()
                .iosSheetChrome(Text(title))
        }
        #endif
    }
}
