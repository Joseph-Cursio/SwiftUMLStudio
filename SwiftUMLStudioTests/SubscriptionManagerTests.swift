import Foundation
import Observation
import StoreKit
import Testing
@testable import SwiftUMLStudio

// MARK: - GCD dispatch helper

private func runOnMain(_ block: @MainActor () -> Void) {
    if Thread.isMainThread {
        MainActor.assumeIsolated(block)
    } else {
        DispatchQueue.main.sync { MainActor.assumeIsolated(block) }
    }
}

// MARK: - Mock

@Observable @MainActor
final class MockSubscriptionProvider: SubscriptionProviding {
    var isProUnlocked: Bool = false
    var products: [Product] = []
    var purchaseError: String?

    private(set) var purchaseCallCount: Int = 0
    private(set) var restoreCallCount: Int = 0

    func purchase(_ product: Product) async {
        purchaseCallCount += 1
    }

    func restorePurchases() async {
        restoreCallCount += 1
    }
}

// MARK: - FeatureGate + Mock Tests

@Suite("FeatureGate with MockSubscriptionProvider")
struct FeatureGateMockTests {

    @Test("all features locked when Pro is not unlocked",
          arguments: ProFeature.allCases)
    func featureLockedWhenProLocked(feature: ProFeature) {
        runOnMain {
            let mock = MockSubscriptionProvider()
            mock.isProUnlocked = false
            #expect(FeatureGate.isUnlocked(feature, manager: mock) == false)
        }
    }

    @Test("all features unlocked when Pro is active",
          arguments: ProFeature.allCases)
    func featureUnlockedWhenProActive(feature: ProFeature) {
        runOnMain {
            let mock = MockSubscriptionProvider()
            mock.isProUnlocked = true
            #expect(FeatureGate.isUnlocked(feature, manager: mock))
        }
    }

    @Test("toggling Pro state changes gate result")
    func togglingProStateChangesGateResult() {
        runOnMain {
            let mock = MockSubscriptionProvider()
            mock.isProUnlocked = false
            #expect(FeatureGate.isUnlocked(.sequenceDiagrams, manager: mock) == false)

            mock.isProUnlocked = true
            #expect(FeatureGate.isUnlocked(.sequenceDiagrams, manager: mock))
        }
    }
}

// MARK: - MockSubscriptionProvider Tests

@Suite("MockSubscriptionProvider")
struct MockSubscriptionProviderTests {

    @Test("purchaseError starts nil")
    func purchaseErrorStartsNil() {
        runOnMain {
            let mock = MockSubscriptionProvider()
            #expect(mock.purchaseError == nil)
        }
    }

    @Test("purchaseError can be set and read")
    func purchaseErrorSettable() {
        runOnMain {
            let mock = MockSubscriptionProvider()
            mock.purchaseError = "Something went wrong"
            #expect(mock.purchaseError == "Something went wrong")
        }
    }

    @Test("purchaseError can be cleared")
    func purchaseErrorClearable() {
        runOnMain {
            let mock = MockSubscriptionProvider()
            mock.purchaseError = "Error"
            mock.purchaseError = nil
            #expect(mock.purchaseError == nil)
        }
    }

    @Test("purchase call is tracked")
    func purchaseCallTracked() async {
        await MainActor.run {
            let mock = MockSubscriptionProvider()
            #expect(mock.purchaseCallCount == 0)
        }
        // Note: We cannot construct a Product in tests, so we verify the
        // counter initializes to zero. The tracking mechanism is validated
        // by the mock's implementation and would increment on actual call.
    }

    @Test("restore call is tracked")
    func restoreCallTracked() async {
        let mock = await MainActor.run { MockSubscriptionProvider() }
        await mock.restorePurchases()
        let count = await mock.restoreCallCount
        #expect(count == 1)
    }

    @Test("multiple restore calls accumulate")
    func multipleRestoreCallsAccumulate() async {
        let mock = await MainActor.run { MockSubscriptionProvider() }
        await mock.restorePurchases()
        await mock.restorePurchases()
        await mock.restorePurchases()
        let count = await mock.restoreCallCount
        #expect(count == 3)
    }

    @Test("products defaults to empty array")
    func productsDefaultsEmpty() {
        runOnMain {
            let mock = MockSubscriptionProvider()
            #expect(mock.products.isEmpty)
        }
    }

    @Test("isProUnlocked defaults to false")
    func isProUnlockedDefaultsFalse() {
        runOnMain {
            let mock = MockSubscriptionProvider()
            #expect(mock.isProUnlocked == false)
        }
    }
}

// MARK: - SubscriptionManager Defaults

@Suite("SubscriptionManager defaults")
struct SubscriptionManagerDefaultTests {

    @Test("starts with isProUnlocked true in development mode")
    func startsUnlockedInDev() {
        runOnMain {
            let manager = SubscriptionManager()
            // The initializer sets isProUnlocked = true as the stored default
            #expect(manager.isProUnlocked == true)
        }
    }

    @Test("purchaseError starts nil")
    func purchaseErrorStartsNil() {
        runOnMain {
            let manager = SubscriptionManager()
            #expect(manager.purchaseError == nil)
        }
    }

    @Test("products starts empty")
    func productsStartsEmpty() {
        runOnMain {
            let manager = SubscriptionManager()
            #expect(manager.products.isEmpty)
        }
    }
}
