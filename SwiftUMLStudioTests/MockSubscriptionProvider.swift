import Observation
import StoreKit
@testable import SwiftUMLStudio

// MARK: - GCD dispatch helper

// MARK: - Mock

@Observable @MainActor
final class MockSubscriptionProvider: SubscriptionProviding {
    var isProUnlocked: Bool = false
    var products: [Product] = []
    var purchaseError: String?

    private(set) var purchaseCallCount: Int = 0
    private(set) var restoreCallCount: Int = 0

    func purchase(_: Product) {
        purchaseCallCount += 1
    }

    func restorePurchases() {
        restoreCallCount += 1
    }
}
