import StoreKit

/// Manages in-app purchases: premium unlock (5+ medicines) and donations.
@MainActor
final class StoreManager: ObservableObject {
    static let shared = StoreManager()

    // Product identifiers
    static let premiumID = "com.konamon.app.premium"
    static let donation200ID = "com.konamon.app.donation.200"
    static let donation500ID = "com.konamon.app.donation.500"

    /// Free tier medicine registration limit.
    static let freeLimit = 5

    @Published var isPremium = false
    @Published var products: [Product] = []
    @Published var purchaseError: String?
    /// Shared flag to present PaywallView from anywhere in the app.
    @Published var showPaywall = false

    private var updateListener: Task<Void, Error>?

    init() {
        updateListener = listenForTransactions()
        Task { await checkPurchaseStatus() }
    }

    deinit {
        updateListener?.cancel()
    }

    // MARK: - Load Products

    func loadProducts() async {
        do {
            let ids: Set<String> = [
                Self.premiumID,
                Self.donation200ID,
                Self.donation500ID,
            ]
            products = try await Product.products(for: ids)
                .sorted { $0.price < $1.price }
        } catch {
            purchaseError = "商品情報の読み込みに失敗しました。"
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await checkPurchaseStatus()
            case .userCancelled:
                break
            case .pending:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = "購入に失敗しました: \(error.localizedDescription)"
        }
    }

    // MARK: - Restore

    func restore() async {
        try? await AppStore.sync()
        await checkPurchaseStatus()
    }

    // MARK: - Status Check

    func checkPurchaseStatus() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if transaction.productID == Self.premiumID {
                    isPremium = true
                    return
                }
            }
        }
        isPremium = false
    }

    /// Whether the user can register more medicines (within free limit or premium).
    var canRegisterMore: Bool {
        if isPremium { return true }
        let currentCount = MedicineService.userEntries().count
        return currentCount < Self.freeLimit
    }

    // MARK: - Private

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self.checkPurchaseStatus()
                }
            }
        }
    }

    enum StoreError: Error {
        case failedVerification
    }
}
