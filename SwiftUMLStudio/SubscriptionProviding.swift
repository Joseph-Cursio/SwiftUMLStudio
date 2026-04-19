import StoreKit

/// Protocol abstracting the subscription interface for testability.
/// Consumers depend on this protocol instead of the concrete `SubscriptionManager`,
/// enabling mock injection in tests.
@MainActor
protocol SubscriptionProviding: AnyObject, Observable {
    var isProUnlocked: Bool { get }
    var products: [Product] { get }
    var purchaseError: String? { get set }

    func purchase(_ product: Product) async
    func restorePurchases() async
}

extension SubscriptionManager: SubscriptionProviding {}
