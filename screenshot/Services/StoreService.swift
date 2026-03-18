import AppKit
import StoreKit

@MainActor
@Observable
final class StoreService {
    enum PaywallContext {
        case general
        case projectLimit
        case rowLimit
        case templateLimit

        var title: String {
            switch self {
            case .general:
                "Unlock Screenshot Bro Pro"
            case .projectLimit:
                "Create More Projects"
            case .rowLimit:
                "Add More Rows"
            case .templateLimit:
                "Add More Screenshots"
            }
        }

        var message: String {
            switch self {
            case .general:
                "Use StoreKit to unlock the full editor with a single App Store purchase."
            case .projectLimit:
                "The free plan includes one project. Upgrade to Pro to create and duplicate as many projects as you need."
            case .rowLimit:
                "The free plan includes up to \(StoreService.freeMaxRows) rows per project. Upgrade to keep expanding your layout."
            case .templateLimit:
                "The free plan includes up to \(StoreService.freeMaxTemplatesPerRow) screenshots per row. Upgrade to keep adding variants."
            }
        }
    }

    enum PurchaseOperation: Equatable {
        case purchase
        case restore

        var progressTitle: String {
            switch self {
            case .purchase:
                "Contacting the App Store…"
            case .restore:
                "Checking your purchase history…"
            }
        }
    }

    static let productId = "proversion"

    private(set) var isProUnlocked = false
    private(set) var proProduct: Product?
    private(set) var purchaseError: String?
    private(set) var purchaseInfo: String?
    private(set) var isLoading = false
    private(set) var didFinishLoadingProducts = false
    private(set) var showPaywall = false
    private(set) var paywallContext: PaywallContext = .general
    private(set) var activeOperation: PurchaseOperation?

    private var updatesTask: Task<Void, Never>?

    // MARK: - Free tier limits

    nonisolated static let freeMaxRows = 3
    nonisolated static let freeMaxTemplatesPerRow = 10

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
        showPaywall = true
    }

    func dismissPaywall() {
        showPaywall = false
    }

    // MARK: - Lifecycle

    func start() {
        updatesTask?.cancel()
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                await self.handle(transactionResult: result, shouldSurfaceVerificationFailure: false)
            }
        }

        Task {
            await loadProducts()
            await refreshPurchaseStatus()
        }
    }

    // MARK: - Products

    private func loadProducts() async {
        do {
            let products = try await Product.products(for: [Self.productId])
            proProduct = products.first(where: { $0.id == Self.productId })
            if proProduct == nil {
                purchaseError = "Product not found. Please try again later."
            } else if purchaseError == "Product not found. Please try again later." {
                purchaseError = nil
            }
        } catch {
            purchaseError = "Failed to load products: \(error.localizedDescription)"
        }
        didFinishLoadingProducts = true
    }

    // MARK: - Purchase status

    func refreshPurchaseStatus(showVerificationFailure: Bool = false) async {
        let entitlement = await Transaction.currentEntitlement(for: Self.productId)

        switch entitlement {
        case .verified(let transaction):
            isProUnlocked = transaction.revocationDate == nil
        case .unverified(_, let error):
            isProUnlocked = false
            if showVerificationFailure {
                purchaseError = "We couldn’t verify your purchase with the App Store: \(error.localizedDescription)"
            }
        case nil:
            isProUnlocked = false
        }
    }

    // MARK: - Purchase

    func purchase(confirmIn window: NSWindow? = nil) async {
        guard !isLoading else { return }

        guard let product = proProduct else {
            purchaseError = "Product not available. Please try again later."
            return
        }

        if isProUnlocked {
            purchaseInfo = "Screenshot Bro Pro is already unlocked on this Mac."
            purchaseError = nil
            return
        }

        beginOperation(.purchase)
        defer { endOperation() }

        do {
            let result: Product.PurchaseResult
            let confirmationWindow = window ?? NSApp.keyWindow
            if #available(macOS 15.2, *), let confirmationWindow {
                result = try await product.purchase(confirmIn: confirmationWindow)
            } else {
                result = try await product.purchase()
            }

            switch result {
            case .success(let verification):
                if await handle(transactionResult: verification, shouldSurfaceVerificationFailure: true) {
                    purchaseInfo = "Screenshot Bro Pro is now unlocked."
                    showPaywall = false
                }
            case .userCancelled:
                break
            case .pending:
                purchaseInfo = "This purchase is pending approval."
            @unknown default:
                break
            }
        } catch {
            purchaseError = errorMessage(for: error, during: .purchase)
        }
    }

    // MARK: - Restore

    func restore() async {
        guard !isLoading else { return }

        let wasUnlocked = isProUnlocked
        beginOperation(.restore)
        defer { endOperation() }

        do {
            try await AppStore.sync()
            await refreshPurchaseStatus(showVerificationFailure: true)
            if isProUnlocked {
                purchaseInfo = wasUnlocked
                    ? "Screenshot Bro Pro is already unlocked on this Mac."
                    : "Your Screenshot Bro Pro purchase was restored."
                showPaywall = false
            } else {
                purchaseInfo = "No previous Screenshot Bro Pro purchase was found for this Apple Account."
            }
        } catch {
            purchaseError = errorMessage(for: error, during: .restore)
        }
    }

    // MARK: - Transaction handling

    @discardableResult
    private func handle(
        transactionResult result: VerificationResult<Transaction>,
        shouldSurfaceVerificationFailure: Bool
    ) async -> Bool {
        switch result {
        case .verified(let transaction):
            if transaction.productID == Self.productId {
                isProUnlocked = transaction.revocationDate == nil
            }
            await transaction.finish()
            return transaction.productID == Self.productId && transaction.revocationDate == nil
        case .unverified(_, let error):
            if shouldSurfaceVerificationFailure {
                purchaseError = "We couldn’t verify the App Store transaction: \(error.localizedDescription)"
            }
            return false
        }
    }

    private func beginOperation(_ operation: PurchaseOperation) {
        activeOperation = operation
        isLoading = true
        purchaseError = nil
        purchaseInfo = nil
    }

    private func endOperation() {
        activeOperation = nil
        isLoading = false
    }

    private func errorMessage(for error: Error, during operation: PurchaseOperation) -> String {
        let prefix = operation == .purchase ? "Purchase failed" : "Restore failed"

        if let purchaseError = error as? Product.PurchaseError {
            switch purchaseError {
            case .purchaseNotAllowed:
                return "Purchases are not allowed for this Apple Account."
            case .productUnavailable:
                return "This purchase is currently unavailable in the App Store."
            default:
                return "\(prefix): \(purchaseError.localizedDescription)"
            }
        }

        return "\(prefix): \(error.localizedDescription)"
    }
}
