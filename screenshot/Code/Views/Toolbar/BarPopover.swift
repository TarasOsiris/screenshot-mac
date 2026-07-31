import SwiftUI

/// How `barPopover` presents on iOS. macOS ignores it and always shows an anchored popover.
enum BarPopoverStyle {
    /// iPad: a panel docked above the properties bar, leaving the canvas visible and interactive.
    /// iPhone (compact) falls back to the sheet — a bottom sheet is already bottom-anchored there.
    case panel
    /// Always the modal sheet. For sheet-scale content: long lists, or text fields that a
    /// bottom-docked panel would leave under the software keyboard.
    case sheet
}

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
                // The presenting bar leaks its compact font/controlSize into the sheet's
                // environment — reset both so sheet content gets standard iPad typography.
                .font(nil)
                .controlSize(.regular)
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
        // Multiple detents → show the grabber so the resize affordance is discoverable.
        .presentationDetents(detents)
        .presentationDragIndicator(detents.count > 1 ? .visible : .hidden)
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
    /// macOS shows a real popover above the anchor (`arrowEdge: .top`). A popover anchored to a
    /// control sitting at the very bottom of an iOS screen renders partly off-screen, so:
    /// iPad docks a floating panel above the bar (`.panel`, the default — the canvas behind stays
    /// undimmed and interactive), and iPhone uses a resizable bottom sheet.
    ///
    /// `scrollableContent`: pass `true` for plain `VStack` content so the presentation adds a
    /// `ScrollView` around it. Leave `false` (default) for self-scrolling `Form`/`List`
    /// content — wrapping those in a `ScrollView` collapses them to zero height (empty sheet).
    @ViewBuilder
    func barPopover<Content: View>(
        isPresented: Binding<Bool>,
        title: LocalizedStringKey,
        scrollableContent: Bool = false,
        style: BarPopoverStyle = .panel,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        #if os(macOS)
        popover(isPresented: isPresented, arrowEdge: .top, content: content)
        #else
        modifier(BarPopoverPresentation(
            isPresented: isPresented,
            title: title,
            scrollableContent: scrollableContent,
            style: style,
            panelContent: content
        ))
        #endif
    }

    /// Width for content shown via `barPopover`. macOS popover / iPad centered-card sheets
    /// use the supplied fixed width; the iPhone full-width sheet fills instead, so the editor
    /// reads like the row background editor rather than a narrow floating column.
    @ViewBuilder
    func barPopoverContentWidth(_ width: CGFloat) -> some View {
        #if os(macOS)
        frame(width: width)
        #else
        modifier(BarPopoverContentWidth(regularWidth: width))
        #endif
    }
}

#if os(iOS)
private struct BarPopoverContentWidth: ViewModifier {
    let regularWidth: CGFloat
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    func body(content: Content) -> some View {
        if horizontalSizeClass == .compact {
            content.frame(maxWidth: .infinity)
        } else {
            content.frame(width: regularWidth)
        }
    }
}

/// Detents for a bottom-bar sheet. iPhone (compact) can half-open via a grabber + medium
/// detent to keep the canvas visible; iPad keeps the single full-height floating card.
enum BarSheet {
    static func detents(compact: Bool) -> Set<PresentationDetent> {
        compact ? [.medium, .large] : [.large]
    }
}

/// Picks the iOS presentation for `barPopover`. The size class can only be read from inside a
/// view, hence a modifier rather than a branch in the `barPopover` builder itself.
private struct BarPopoverPresentation<PanelContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let title: LocalizedStringKey
    let scrollableContent: Bool
    let style: BarPopoverStyle
    @ViewBuilder let panelContent: () -> PanelContent

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var usesDockedPanel: Bool { style == .panel && horizontalSizeClass != .compact }

    func body(content: Content) -> some View {
        if usesDockedPanel {
            content.modifier(BarPanelPresenter(
                isPresented: $isPresented,
                title: title,
                scrollableContent: scrollableContent,
                panelContent: panelContent
            ))
        } else {
            content.sheet(isPresented: $isPresented) {
                BarPopoverSheet(title: Text(title), scrollableContent: scrollableContent, content: panelContent)
            }
        }
    }
}

/// Bottom-bar popover content as an iOS sheet, with a native nav bar + Done button and
/// (on iPhone) a resizable, half-openable detent. `Form`/`List` content scrolls itself and
/// is presented directly; plain `VStack` content (`scrollableContent: true`) is wrapped in a
/// `ScrollView` so it can overflow the detent — wrapping a `Form`/`List` instead would
/// collapse it to zero height (an empty sheet).
private struct BarPopoverSheet<Content: View>: View {
    let title: Text
    var scrollableContent: Bool = false
    @ViewBuilder let content: () -> Content
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isPhone: Bool { horizontalSizeClass == .compact }

    var body: some View {
        Group {
            if scrollableContent {
                ScrollView {
                    content().frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                content()
            }
        }
        .iosSheetChrome(title, detents: BarSheet.detents(compact: isPhone))
        // Half-open (iPhone medium detent) stops dimming the canvas, so the shape being edited
        // stays visible and draggable; expanding to `.large` goes modal again.
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }
}
#endif
