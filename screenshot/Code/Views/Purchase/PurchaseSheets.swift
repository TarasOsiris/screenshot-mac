import SwiftUI

extension View {
    /// The paywall and the post-purchase celebration that follows it, held back while `suppressed`.
    func purchaseSheets(
        store: PurchaseService,
        restoring hostScreen: AnalyticsService.Screen,
        suppressed: Bool = false
    ) -> some View {
        modifier(PurchaseSheets(store: store, hostScreen: hostScreen, suppressed: suppressed))
    }
}

private struct PurchaseSheets: ViewModifier {
    let store: PurchaseService
    let hostScreen: AnalyticsService.Screen
    let suppressed: Bool

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: paywallPresented,
                   onDismiss: { store.presentPendingCelebrationIfNeeded() }) {
                PaywallSheetContent(store: store)
                    .screenView(.paywall, restoring: hostScreen)
            }
            .sheet(isPresented: celebrationPresented) {
                PostPurchaseCelebrationView(context: store.purchaseCelebrationContext ?? .general) {
                    store.dismissPurchaseCelebration()
                }
                .screenView(.purchaseCelebration, restoring: hostScreen)
            }
    }

    private var paywallPresented: Binding<Bool> {
        Binding(get: { store.showPaywall && !suppressed }, set: { _ in store.dismissPaywall() })
    }

    private var celebrationPresented: Binding<Bool> {
        Binding(get: { store.purchaseCelebrationContext != nil && !suppressed },
                set: { if !$0 { store.dismissPurchaseCelebration() } })
    }
}
