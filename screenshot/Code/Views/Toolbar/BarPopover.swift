import SwiftUI

#if os(iOS)
/// iPad sheet chrome: a `NavigationStack` with an inline title and native toolbar
/// Done/Cancel actions. macOS keeps its own popover/window chrome, so this type is
/// iOS-only and `iosSheetChrome` is a no-op there. Titles are `Text` so callers can pass
/// either a localized literal (`Text("Done")`) or a runtime string (`Text(verbatim:)`).
private struct IOSSheetChrome<Content: View, Confirm: View>: View {
    let title: Text
    let showsCancel: Bool
    let onCancel: (() -> Void)?
    let detents: Set<PresentationDetent>
    @ViewBuilder let confirm: (DismissAction) -> Confirm
    @ViewBuilder let content: () -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if showsCancel {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(role: .cancel) { onCancel?(); dismiss() } label: { Text("Cancel") }
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) { confirm(dismiss) }
                }
        }
        // A single fixed detent by default: no drag handle / resizing. Compact sheets pass a
        // `.height(...)` detent so a one-field dialog isn't presented full-screen.
        // (Not `.presentationSizing(.fitted)`, which collapses a NavigationStack to just the
        // nav bar.) `.fullScreenCover` (showcase export) ignores this, which is fine.
        .presentationDetents(detents)
    }
}

/// The prominent confirm control shared by both chrome variants — a borderedProminent icon
/// button with a pinned font/control size so it looks identical regardless of the controlSize
/// the presenting bar leaks into the sheet.
private struct IOSConfirmLabel: View {
    let systemImage: String
    var body: some View {
        Image(systemName: systemImage).font(.body.weight(.semibold))
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
        confirmSystemImage: String = "checkmark",
        confirmDisabled: Bool = false,
        showsCancel: Bool = false,
        detents: Set<PresentationDetent> = [.large],
        onConfirm: (() -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) -> some View {
        #if os(iOS)
        IOSSheetChrome(title: title, showsCancel: showsCancel, onCancel: onCancel, detents: detents, confirm: { dismiss in
            // The confirm action owns dismissal: a bare "Done" dismisses, but a supplied
            // onConfirm decides (e.g. SvgPasteDialog stays open and shows an error on failure).
            Button {
                if let onConfirm { onConfirm() } else { dismiss() }
            } label: {
                IOSConfirmLabel(systemImage: confirmSystemImage)
            }
            .iPadToolbarProminentStyle()
            .controlSize(.regular)
            .disabled(confirmDisabled)
            .accessibilityLabel(confirmTitle)
        }, content: { self })
        #else
        self
        #endif
    }

    /// Like `iosSheetChrome`, but the confirm action is a pull-down `Menu` instead of a button —
    /// used when the sheet stays open and the user picks a destination (e.g. showcase export:
    /// Save to Photos / Files / Share). No-op on macOS.
    @ViewBuilder
    func iosSheetChrome<MenuItems: View>(
        _ title: Text,
        confirmTitle: Text,
        confirmSystemImage: String,
        confirmDisabled: Bool = false,
        showsCancel: Bool = false,
        onCancel: (() -> Void)? = nil,
        @ViewBuilder confirmMenu: @escaping () -> MenuItems
    ) -> some View {
        #if os(iOS)
        IOSSheetChrome(title: title, showsCancel: showsCancel, onCancel: onCancel, detents: [.large], confirm: { _ in
            Menu {
                confirmMenu()
            } label: {
                IOSConfirmLabel(systemImage: confirmSystemImage)
            }
            .iPadToolbarProminentStyle()
            .controlSize(.regular)
            .disabled(confirmDisabled)
            .accessibilityLabel(confirmTitle)
        }, content: { self })
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
