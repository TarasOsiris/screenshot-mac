import StoreKit

@MainActor
@Observable
final class StoreService {
    static let productId = "proversion"

    private(set) var isProUnlocked = false
    private(set) var proProduct: Product?
    private(set) var purchaseError: String?
    private(set) var purchaseInfo: String?
    private(set) var isLoading = false
    private(set) var didFinishLoadingProducts = false
    private(set) var showPaywall = false

    private var updatesTask: Task<Void, Never>?

    // MARK: - Free tier limits

    static let freeMaxRows = 3
    static let freeMaxTemplatesPerRow = 10

    func canAddRow(currentCount: Int) -> Bool {
        isProUnlocked || currentCount < Self.freeMaxRows
    }

    func canAddTemplate(currentCount: Int) -> Bool {
        isProUnlocked || currentCount < Self.freeMaxTemplatesPerRow
    }

    func canCreateProject() -> Bool {
        isProUnlocked
    }

    func requirePro(allowed: Bool, action: () -> Void) {
        if allowed {
            action()
        } else {
            showPaywall = true
        }
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
                await self.handle(transactionResult: result)
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
            proProduct = products.first
            if proProduct == nil {
                purchaseError = "Product not found. Please try again later."
            }
        } catch {
            purchaseError = "Failed to load products: \(error.localizedDescription)"
        }
        didFinishLoadingProducts = true
    }

    // MARK: - Purchase status

    func refreshPurchaseStatus() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productId {
                entitled = true
                break
            }
        }
        if isProUnlocked != entitled {
            isProUnlocked = entitled
        }
    }

    // MARK: - Purchase

    func purchase() async {
        guard let product = proProduct else {
            purchaseError = "Product not available. Please try again later."
            return
        }

        isLoading = true
        purchaseError = nil
        purchaseInfo = nil

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                await handle(transactionResult: verification)
            case .userCancelled:
                break
            case .pending:
                purchaseInfo = "Purchase is pending approval."
            @unknown default:
                break
            }
        } catch {
            purchaseError = "Purchase failed: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Restore

    func restore() async {
        isLoading = true
        purchaseError = nil
        purchaseInfo = nil

        do {
            try await AppStore.sync()
            await refreshPurchaseStatus()
            if !isProUnlocked {
                purchaseInfo = "No previous purchase found."
            }
        } catch {
            purchaseError = "Restore failed: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Transaction handling

    private func handle(transactionResult result: VerificationResult<Transaction>) async {
        switch result {
        case .verified(let transaction):
            if transaction.productID == Self.productId, !isProUnlocked {
                isProUnlocked = true
            }
            await transaction.finish()
        case .unverified:
            break
        }
    }
}
