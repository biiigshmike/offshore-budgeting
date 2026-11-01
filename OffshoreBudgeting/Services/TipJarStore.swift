import Observation
import StoreKit

@MainActor
@Observable
final class TipJarStore {
    static let shared = TipJarStore()
    static let productIDs = [
        "com.mb.offshore_budgeting.tip.small",
        "com.mb.offshore_budgeting.tip.medium",
        "com.mb.offshore_budgeting.tip.large"
    ]

    private(set) var products: [Product] = []
    private(set) var isLoading = false
    private(set) var isPurchasing = false
    var message: String?
    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    private init() { }

    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.complete(result)
            }
        }
        Task {
            for await result in Transaction.unfinished {
                await complete(result)
            }
        }
    }

    func loadProducts() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let available = try await Product.products(for: Self.productIDs)
            products = available.filter { $0.type == .consumable }.sorted { $0.price < $1.price }
        } catch {
            products = []
            message = String(localized: "Couldn’t load tips. Please check your connection and try again.")
        }
    }

    func purchase(_ product: Product) async {
        guard !isPurchasing, AppStore.canMakePayments else {
            message = String(localized: "Purchases are currently unavailable on this device.")
            return
        }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let result):
                await complete(result)
            case .pending:
                message = String(localized: "Your tip is awaiting approval. Thank you! Apple will complete it once approved.")
            case .userCancelled:
                break
            @unknown default:
                message = String(localized: "The purchase hasn’t completed. Please try again later.")
            }
        } catch {
            message = String(localized: "Couldn’t complete your tip. Please try again later.")
        }
    }

    private func complete(_ result: VerificationResult<Transaction>) async {
        switch result {
        case .verified(let transaction):
            guard Self.productIDs.contains(transaction.productID) else { return }
            // Tips grant no entitlement or financial ledger entry. Finishing allows repeat tips.
            await transaction.finish()
            if transaction.revocationDate == nil {
                message = String(localized: "Thank you for supporting Offshore! Your kindness helps keep the app growing.")
            }
        case .unverified:
            message = String(localized: "Apple couldn’t verify this purchase. Please try again later.")
        }
    }
}
