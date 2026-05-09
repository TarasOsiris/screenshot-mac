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

    enum ProTier: Equatable {
        case lifetime
        case subscription(productId: String, expirationDate: Date, willRenew: Bool)

        var displayName: String {
            switch self {
            case .lifetime:
                return String(localized: "Lifetime")
            case .subscription(let productId, _, _):
                let lower = productId.lowercased()
                if lower.contains("year") || lower.contains("annual") {
                    return String(localized: "Pro — Yearly")
                }
                if lower.contains("month") {
                    return String(localized: "Pro — Monthly")
                }
                if lower.contains("week") {
                    return String(localized: "Pro — Weekly")
                }
                return String(localized: "Pro — Subscription")
            }
        }
    }

    static let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")!

    private static let revenueCatAPIKeyEnvironmentName = "REVENUECAT_API_KEY"
    private static let revenueCatAPIKeyInfoDictionaryKey = "REVENUECAT_API_KEY"
    private static let revenueCatEntitlementIDEnvironmentName = "REVENUECAT_ENTITLEMENT_ID"
    private static let revenueCatEntitlementIDInfoDictionaryKey = "REVENUECAT_ENTITLEMENT_ID"
    private static let revenueCatProductIDEnvironmentName = "REVENUECAT_PRODUCT_ID"
    private static let revenueCatProductIDInfoDictionaryKey = "REVENUECAT_PRODUCT_ID"
    #if DEBUG
    private static let forceProUnlockEnvironmentName = "SCREENSHOT_FORCE_PRO_UNLOCK"
    #endif
    private static let fallbackEntitlementId = "Nineva Studios / ScreenshotBro Pro"
    private static let fallbackProductId = "proversion"
    #if DEBUG
    private static let debugFallbackAPIKey = "test_KgNxrrXqBIGgiORjBPsdiXrraJL"
    #endif

    private(set) var isProUnlocked = false
    private(set) var proTier: ProTier?
    private(set) var showPaywall = false
    private(set) var paywallContext: PaywallContext = .general
    private(set) var purchaseCelebrationContext: PaywallContext?
    private(set) var configurationIssue: String?
    private(set) var purchaseStatusMessage: String?
    private(set) var purchaseStatusIsError = false

    private var delegate: CustomerInfoDelegate?
    private var didStart = false

    // MARK: - Free tier limits

    nonisolated static let freeMaxRows = 3
    nonisolated static let freeMaxTemplatesPerRow = 5

    #if DEBUG
    private static let isForceProUnlockedForCurrentProcess: Bool = {
        let value = ProcessInfo.processInfo.environment[forceProUnlockEnvironmentName]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return value == "1" || value == "true" || value == "yes"
    }()
    #endif

    func canAddRow(currentCount: Int) -> Bool {
        isProUnlocked || currentCount < Self.freeMaxRows
    }

    func canAddTemplate(currentCount: Int) -> Bool {
        isProUnlocked || currentCount < Self.freeMaxTemplatesPerRow
    }

    func canCreateProject() -> Bool {
        #if DEBUG
        return isProUnlocked || Self.isForceProUnlockedForCurrentProcess
        #else
        return isProUnlocked
        #endif
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

    func dismissPurchaseCelebration() {
        purchaseCelebrationContext = nil
    }

    // MARK: - Lifecycle

    func start() {
        guard !didStart else { return }
        didStart = true

        #if DEBUG
        if Self.isForceProUnlockedForCurrentProcess {
            isProUnlocked = true
            configurationIssue = nil
            return
        }
        #endif

        #if DEBUG
        Purchases.logLevel = .debug
        #endif

        guard let apiKey = Self.resolvedAPIKey() else {
            configurationIssue = String(localized: "RevenueCat API key is missing. Set REVENUECAT_API_KEY in the app environment or Info.plist.")
            return
        }

        #if !DEBUG
        guard !apiKey.hasPrefix("test_") else {
            configurationIssue = String(localized: "RevenueCat is configured with a Test Store API key. Replace it with your Apple public SDK key before shipping.")
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
            #if DEBUG
            await debugDumpOfferings()
            #endif
        }
    }

    #if DEBUG
    private func debugDumpOfferings() async {
        let bundleVersion = Bundle.main.shortVersion.isEmpty ? "?" : Bundle.main.shortVersion
        let bundleBuild = Bundle.main.buildNumber.isEmpty ? "?" : Bundle.main.buildNumber
        print("[Store] bundle short version: \(bundleVersion) (build \(bundleBuild))")

        Purchases.shared.invalidateCustomerInfoCache()
        do {
            _ = try await Purchases.shared.customerInfo(fetchPolicy: .fetchCurrent)
            let offerings = try await Purchases.shared.offerings()
            print("[Store] current offering id: \(offerings.current?.identifier ?? "<nil>")")
            let currentPackages = offerings.current?.availablePackages.map { pkg in
                "\(pkg.identifier)→\(pkg.storeProduct.productIdentifier)"
            } ?? []
            print("[Store] current packages: \(currentPackages)")
            print("[Store] all offerings: \(offerings.all.keys.sorted())")
            for (id, offering) in offerings.all {
                let packages = offering.availablePackages.map { pkg in
                    "\(pkg.identifier)→\(pkg.storeProduct.productIdentifier)"
                }
                print("[Store]   \(id): \(packages)")
            }
        } catch {
            print("[Store] offerings fetch failed: \(error)")
        }
    }
    #endif

    // MARK: - Entitlement

    private func refreshEntitlementStatus() async {
        guard Purchases.isConfigured else { return }

        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            updateEntitlement(from: customerInfo)
        } catch {
            setPurchaseStatus(String(localized: "Failed to refresh purchase status: \(error.localizedDescription)"), isError: true)
        }
    }

    private func updateEntitlement(from customerInfo: CustomerInfo) {
        let activeEntitlements = customerInfo.entitlements.active
        let configuredEntitlementId = Self.resolvedEntitlementID()
        let configuredProductId = Self.resolvedProductID()
        let configuredEntitlement = configuredEntitlementId.flatMap { activeEntitlements[$0] }
        let hasConfiguredEntitlement = configuredEntitlement?.isActive == true
        let hasSingleActiveEntitlement = activeEntitlements.count == 1 && activeEntitlements.values.first?.isActive == true
        let hasPurchasedConfiguredProduct = configuredProductId.map(customerInfo.allPurchasedProductIdentifiers.contains) == true
        let entitled = hasConfiguredEntitlement || hasSingleActiveEntitlement || hasPurchasedConfiguredProduct
        #if DEBUG
        if !entitled && (!activeEntitlements.isEmpty || !customerInfo.allPurchasedProductIdentifiers.isEmpty) {
            let configuredEntitlementId = configuredEntitlementId ?? "<none>"
            let configuredProductId = configuredProductId ?? "<none>"
            let activeEntitlementKeys = activeEntitlements.keys.sorted().joined(separator: ", ")
            let purchasedProductIds = customerInfo.allPurchasedProductIdentifiers.sorted().joined(separator: ", ")
            print("[StoreService] No Pro unlock for entitlement '\(configuredEntitlementId)' or product '\(configuredProductId)'. Active entitlements: \(activeEntitlementKeys). Purchased products: \(purchasedProductIds)")
        }
        #endif
        let newTier: ProTier? = entitled
            ? (configuredEntitlement ?? activeEntitlements.values.first).map(Self.tier(from:))
            : nil

        if isProUnlocked != entitled {
            isProUnlocked = entitled
        }
        if proTier != newTier {
            proTier = newTier
        }
    }

    private static func tier(from entitlement: EntitlementInfo) -> ProTier {
        if let expirationDate = entitlement.expirationDate {
            return .subscription(
                productId: entitlement.productIdentifier,
                expirationDate: expirationDate,
                willRenew: entitlement.willRenew
            )
        }
        return .lifetime
    }

    func handlePurchaseCompleted(_ customerInfo: CustomerInfo) {
        let triggeringContext = paywallContext
        updateEntitlement(from: customerInfo)
        if isProUnlocked {
            showPaywall = false
            purchaseCelebrationContext = triggeringContext
        } else {
            setPurchaseStatus(String(localized: "Purchase completed, but RevenueCat did not grant access. Check the entitlement or product mapping in RevenueCat."), isError: true)
        }
    }

    func handleRestoreCompleted(_ customerInfo: CustomerInfo) {
        updateEntitlement(from: customerInfo)
        if isProUnlocked {
            setPurchaseStatus(String(localized: "Your Screenshot Bro Pro purchase was restored."))
            showPaywall = false
        } else {
            setPurchaseStatus(String(localized: "No Screenshot Bro Pro purchase was found for this Apple Account."), isError: true)
        }
    }

    func handlePurchaseFailure(_ error: Error) {
        setPurchaseStatus(String(localized: "Purchase failed: \(error.localizedDescription)"), isError: true)
    }

    func handleRestoreFailure(_ error: Error) {
        setPurchaseStatus(String(localized: "Restore failed: \(error.localizedDescription)"), isError: true)
    }

    // MARK: - Restore

    func restore() async {
        clearPurchaseStatus()

        guard Purchases.isConfigured else {
            let message = configurationIssue ?? String(localized: "RevenueCat is not configured.")
            setPurchaseStatus(message, isError: true)
            return
        }

        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            updateEntitlement(from: customerInfo)
            if isProUnlocked {
                setPurchaseStatus(String(localized: "Your Screenshot Bro Pro purchase was restored."))
            } else {
                setPurchaseStatus(String(localized: "No Screenshot Bro Pro purchase was found for this Apple Account."))
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

    private static func resolvedEntitlementID() -> String? {
        let environmentKey = ProcessInfo.processInfo.environment[Self.revenueCatEntitlementIDEnvironmentName]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let environmentKey, !environmentKey.isEmpty {
            return environmentKey
        }

        let infoDictionaryKey = (Bundle.main.object(forInfoDictionaryKey: Self.revenueCatEntitlementIDInfoDictionaryKey) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let infoDictionaryKey, !infoDictionaryKey.isEmpty {
            return infoDictionaryKey
        }

        return Self.fallbackEntitlementId
    }

    private static func resolvedProductID() -> String? {
        let environmentKey = ProcessInfo.processInfo.environment[Self.revenueCatProductIDEnvironmentName]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let environmentKey, !environmentKey.isEmpty {
            return environmentKey
        }

        let infoDictionaryKey = (Bundle.main.object(forInfoDictionaryKey: Self.revenueCatProductIDInfoDictionaryKey) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let infoDictionaryKey, !infoDictionaryKey.isEmpty {
            return infoDictionaryKey
        }

        return Self.fallbackProductId
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
