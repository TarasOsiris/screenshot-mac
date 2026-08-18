#if os(iOS)
import SwiftUI

/// Hoists a properties-bar popover's content out of the bar so it can render docked above it.
/// The triggers live inside the bar's horizontal `ScrollView`, so a panel attached to a trigger
/// would be clipped — instead each trigger registers its content here and `ShapePropertiesBar`
/// draws the one open panel. One panel at a time: presenting a second closes the first.
@MainActor
@Observable
final class BarPanelHost {
    struct Panel: Identifiable {
        let id: UUID
        let title: LocalizedStringKey
        let scrollableContent: Bool
        let content: () -> AnyView
        /// Clears the presenting trigger's `isPresented` flag.
        let dismiss: () -> Void
    }

    private(set) var panel: Panel?

    func present(_ panel: Panel) {
        if let current = self.panel, current.id != panel.id {
            current.dismiss()
        }
        self.panel = panel
    }

    func dismiss(id: UUID) {
        guard panel?.id == id else { return }
        panel = nil
    }

    /// Closes whatever is open and tells its trigger, so the bar chip stops reading as active.
    func dismissAll() {
        guard let current = panel else { return }
        panel = nil
        current.dismiss()
    }
}

/// Registers a `barPopover`'s content with the `BarPanelHost` instead of presenting a sheet.
struct BarPanelPresenter<PanelContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let title: LocalizedStringKey
    let scrollableContent: Bool
    @ViewBuilder let panelContent: () -> PanelContent

    @Environment(BarPanelHost.self) private var host: BarPanelHost?
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented, initial: true) { _, presented in
                if presented { present() } else { host?.dismiss(id: id) }
            }
            .onDisappear { host?.dismiss(id: id) }
    }

    private func present() {
        host?.present(
            BarPanelHost.Panel(
                id: id,
                title: title,
                scrollableContent: scrollableContent,
                content: { AnyView(panelContent()) },
                dismiss: { isPresented = false }
            )
        )
    }
}

/// The floating panel itself: bar-matching glass, a title + confirm header, and the registered
/// content below. Deliberately not a sheet — the canvas behind it stays undimmed and interactive
/// so the shape being edited remains visible while its properties change.
struct BarDockedPanel: View {
    let panel: BarPanelHost.Panel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(UIMetrics.Opacity.hairlineOverlay)
            content
        }
        .frame(width: UIMetrics.BarPanel.width)
        .frame(maxHeight: UIMetrics.BarPanel.maxHeight)
        // The bar leaks its compact font/controlSize into the panel — reset both so panel
        // content gets standard iPad typography, same as the sheet chrome does.
        .font(nil)
        .controlSize(.regular)
        .modifier(PropertiesBarChrome())
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(panel.title)
                .font(.headline)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button(action: panel.dismiss) {
                Image(systemName: "checkmark").font(.body.weight(.semibold))
            }
            .iPadToolbarProminentStyle()
            .controlSize(.regular)
            .accessibilityLabel(Text("Done"))
        }
        .padding(.horizontal, UIMetrics.BarPanel.headerHorizontalPadding)
        .padding(.vertical, UIMetrics.BarPanel.headerVerticalPadding)
    }

    @ViewBuilder
    private var content: some View {
        if panel.scrollableContent {
            ScrollView {
                panel.content().frame(maxWidth: .infinity)
            }
        } else {
            // Form/List content scrolls itself; hide its opaque grouped background so the
            // panel's glass shows through.
            panel.content()
                .scrollContentBackground(.hidden)
        }
    }
}
#endif
