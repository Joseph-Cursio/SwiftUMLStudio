@testable import SwiftUMLStudio
import Testing

// MARK: - SubscriptionManager Defaults

@Suite("SubscriptionManager defaults") @MainActor
struct SubscriptionManagerDefaultTests {

    @Test("starts with isProUnlocked true in development mode")
    func startsUnlockedInDev() {
        let manager = SubscriptionManager()
        // The initializer sets isProUnlocked = true as the stored default
        #expect(manager.isProUnlocked == true)
    }

    @Test("purchaseError starts nil")
    func purchaseErrorStartsNil() {
        let manager = SubscriptionManager()
        #expect(manager.purchaseError == nil)
    }

    @Test("products starts empty")
    func productsStartsEmpty() {
        let manager = SubscriptionManager()
        #expect(manager.products.isEmpty)
    }
}
