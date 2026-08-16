import Foundation
import Observation
import StoreKit
import Synchronization

@Observable @MainActor
final class SubscriptionManager {
    private(set) var isProUnlocked: Bool = true
    private(set) var products: [Product] = []
    var purchaseError: String?

    /// The `Transaction.updates` listener, cancelled on deallocation.
    ///
    /// Held in a `Mutex` rather than a `nonisolated(unsafe) var` because the
    /// two accesses sit on opposite sides of this type's isolation: `init`
    /// writes it on the main actor, and `nonisolated deinit` reads it to
    /// cancel. Keeping `deinit` nonisolated means deallocation stays immediate
    /// instead of hopping to the main actor, so the property it touches has to
    /// carry its own synchronisation.
    @ObservationIgnored
    private let transactionListener = Mutex<Task<Void, Never>?>(nil)

    nonisolated static let proMonthlyID = "pro_monthly"
    nonisolated static let proAnnualID = "pro_annual"
    private nonisolated static let productIDs: Set<String> = [proMonthlyID, proAnnualID]

    init() {
        let listener = listenForTransactions()
        transactionListener.withLock { $0 = listener }
        Task { await bootstrap() }
    }

    nonisolated deinit {
        transactionListener.withLock { $0?.cancel() }
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
        isProUnlocked = Self.entitlementResolved(entitled: entitled, productCount: products.count)
    }

    /// Decide the effective Pro-unlocked state given an entitlement check.
    ///
    /// Real entitlements always unlock Pro. When no products load (development
    /// builds without a StoreKit configuration), we also default to unlocked so
    /// the app is usable end-to-end.
    nonisolated static func entitlementResolved(entitled: Bool, productCount: Int) -> Bool {
        entitled || productCount == 0
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
