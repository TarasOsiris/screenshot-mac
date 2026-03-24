import AppKit
import RevenueCat

@MainActor
@Observable
final class StoreService {
    enum PaywallContext {
        case general
        case projectLimit
        case rowLimit
        case templateLimit
    }

    private static let entitlementId = "Nineva Studios / ScreenshotBro Pro"
    private static let revenueCatAPIKeyEnvironmentName = "REVENUECAT_API_KEY"
    private static let revenueCatAPIKeyInfoDictionaryKey = "REVENUECAT_API_KEY"
    #if DEBUG
    private static let debugFallbackAPIKey = "test_KgNxrrXqBIGgiORjBPsdiXrraJL"
    #endif

    private(set) var isProUnlocked = false
    private(set) var showPaywall = false
    private(set) var paywallContext: PaywallContext = .general
    private(set) var configurationIssue: String?
    private(set) var purchaseStatusMessage: String?
    private(set) var purchaseStatusIsError = false

    private var delegate: CustomerInfoDelegate?
    private var didStart = false

    // MARK: - Free tier limits

    nonisolated static let freeMaxRows = 3
    nonisolated static let freeMaxTemplatesPerRow = 5

    func canAddRow(currentCount: Int) -> Bool {
        isProUnlocked || currentCount < Self.freeMaxRows
    }

    func canAddTemplate(currentCount: Int) -> Bool {
        isProUnlocked || currentCount < Self.freeMaxTemplatesPerRow
    }

    func canCreateProject() -> Bool {
        isProUnlocked
    }

    func requirePro(
        allowed: Bool,
        context: PaywallContext = .general,
        action: () -> Void
    ) {
        if allowed {
            action()
        } else {
            presentPaywall(for: context)
        }
    }

    func presentPaywall(for context: PaywallContext = .general) {
        paywallContext = context
        clearPurchaseStatus()
        showPaywall = true
    }

    func dismissPaywall() {
        showPaywall = false
    }

    // MARK: - Lifecycle

    func start() {
        guard !didStart else { return }
        didStart = true

        #if DEBUG
        Purchases.logLevel = .debug
        #endif

        guard let apiKey = Self.resolvedAPIKey() else {
            configurationIssue = "RevenueCat API key is missing. Set REVENUECAT_API_KEY in the app environment or Info.plist."
            return
        }

        #if !DEBUG
        guard !apiKey.hasPrefix("test_") else {
            configurationIssue = "RevenueCat is configured with a Test Store API key. Replace it with your Apple public SDK key before shipping."
            return
        }
        #endif

        Purchases.configure(withAPIKey: apiKey)
        configurationIssue = nil

        let d = CustomerInfoDelegate { [weak self] info in
            self?.updateEntitlement(from: info)
        }
        self.delegate = d
        Purchases.shared.delegate = d

        Task {
            await refreshEntitlementStatus()
        }
    }

    // MARK: - Entitlement

    private func refreshEntitlementStatus() async {
        guard Purchases.isConfigured else { return }

        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            updateEntitlement(from: customerInfo)
        } catch {
            setPurchaseStatus("Failed to refresh purchase status: \(error.localizedDescription)", isError: true)
        }
    }

    private func updateEntitlement(from customerInfo: CustomerInfo) {
        let entitled = customerInfo.entitlements[Self.entitlementId]?.isActive == true
        #if DEBUG
        if !entitled && !customerInfo.entitlements.active.isEmpty {
            print("[StoreService] Entitlement '\(Self.entitlementId)' not found, but active entitlements: \(customerInfo.entitlements.active.keys.joined(separator: ", "))")
        }
        #endif
        isProUnlocked = entitled
    }

    func handlePurchaseOrRestore(_ customerInfo: CustomerInfo) {
        updateEntitlement(from: customerInfo)
        if isProUnlocked {
            clearPurchaseStatus()
            showPaywall = false
        }
    }

    func handlePurchaseFailure(_ error: Error) {
        setPurchaseStatus("Purchase failed: \(error.localizedDescription)", isError: true)
    }

    func handleRestoreFailure(_ error: Error) {
        setPurchaseStatus("Restore failed: \(error.localizedDescription)", isError: true)
    }

    // MARK: - Restore

    func restore() async {
        clearPurchaseStatus()

        guard Purchases.isConfigured else {
            let message = configurationIssue ?? "RevenueCat is not configured."
            setPurchaseStatus(message, isError: true)
            return
        }

        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            updateEntitlement(from: customerInfo)
            if isProUnlocked {
                setPurchaseStatus("Your Screenshot Bro Pro purchase was restored.")
            } else {
                setPurchaseStatus("No Screenshot Bro Pro purchase was found for this Apple Account.")
            }
        } catch {
            handleRestoreFailure(error)
        }
    }

    private func clearPurchaseStatus() {
        purchaseStatusMessage = nil
        purchaseStatusIsError = false
    }

    private func setPurchaseStatus(_ message: String, isError: Bool = false) {
        purchaseStatusMessage = message
        purchaseStatusIsError = isError
    }

    private static func resolvedAPIKey() -> String? {
        let environmentKey = ProcessInfo.processInfo.environment[Self.revenueCatAPIKeyEnvironmentName]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let environmentKey, !environmentKey.isEmpty {
            return environmentKey
        }

        let infoDictionaryKey = (Bundle.main.object(forInfoDictionaryKey: Self.revenueCatAPIKeyInfoDictionaryKey) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let infoDictionaryKey, !infoDictionaryKey.isEmpty {
            return infoDictionaryKey
        }

        #if DEBUG
        return Self.debugFallbackAPIKey
        #else
        return nil
        #endif
    }
}

// MARK: - RevenueCat Delegate

private final class CustomerInfoDelegate: NSObject, PurchasesDelegate, Sendable {
    let onUpdate: @MainActor @Sendable (CustomerInfo) -> Void

    init(onUpdate: @escaping @MainActor @Sendable (CustomerInfo) -> Void) {
        self.onUpdate = onUpdate
    }

    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            onUpdate(customerInfo)
        }
    }
}
