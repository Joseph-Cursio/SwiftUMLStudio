import Foundation
import Observation
import StoreKit

@Observable @MainActor
final class SubscriptionManager {
    private(set) var isProUnlocked: Bool = true
    private(set) var products: [Product] = []
    var purchaseError: String?

    private nonisolated(unsafe) var transactionListener: Task<Void, Never>?

    static let proMonthlyID = "pro_monthly"
    static let proAnnualID = "pro_annual"
    private static let productIDs: Set<String> = [proMonthlyID, proAnnualID]

    init() {
        transactionListener = listenForTransactions()
        Task { await bootstrap() }
    }

    nonisolated deinit {
        transactionListener?.cancel()
    }

    // MARK: - Public

    func purchase(_ product: Product) async {
        purchaseError = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try Self.checkVerified(verification)
                await transaction.finish()
                await checkEntitlement()
            case .userCancelled:
                break
            case .pending:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func restorePurchases() async {
        try? await AppStore.sync()
        await checkEntitlement()
    }

    // MARK: - Private

    private func bootstrap() async {
        await fetchProducts()
        await checkEntitlement()
    }

    private func fetchProducts() async {
        do {
            products = try await Product.products(for: Self.productIDs)
                .sorted { $0.price < $1.price }
        } catch {
            purchaseError = "Failed to load products: \(error.localizedDescription)"
        }
    }

    private func checkEntitlement() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            if let transaction = try? Self.checkVerified(result),
               Self.productIDs.contains(transaction.productID) {
                entitled = true
                break
            }
        }
        // Default to unlocked when no StoreKit configuration is active (development)
        isProUnlocked = entitled || products.isEmpty
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if let transaction = try? Self.checkVerified(result) {
                    await transaction.finish()
                    await self?.checkEntitlement()
                }
            }
        }
    }

    private nonisolated static func checkVerified<PayloadType>(
        _ result: VerificationResult<PayloadType>
    ) throws -> PayloadType {
        switch result {
        case .verified(let payload):
            return payload
        case .unverified(_, let error):
            throw error
        }
    }
}
