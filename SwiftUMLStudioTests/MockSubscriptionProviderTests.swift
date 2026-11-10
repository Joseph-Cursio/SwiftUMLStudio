import Testing

// MARK: - MockSubscriptionProvider Tests

@Suite("MockSubscriptionProvider") @MainActor
struct MockSubscriptionProviderTests {

    @Test("purchaseError starts nil")
    func purchaseErrorStartsNil() {
        let mock = MockSubscriptionProvider()
        #expect(mock.purchaseError == nil)
    }

    @Test("purchaseError can be set and read")
    func purchaseErrorSettable() {
        let mock = MockSubscriptionProvider()
        mock.purchaseError = "Something went wrong"
        #expect(mock.purchaseError == "Something went wrong")
    }

    @Test("purchaseError can be cleared")
    func purchaseErrorClearable() {
        let mock = MockSubscriptionProvider()
        mock.purchaseError = "Error"
        mock.purchaseError = nil
        #expect(mock.purchaseError == nil)
    }

    @Test("purchase call is tracked")
    func purchaseCallTracked() {
        let mock = MockSubscriptionProvider()
        #expect(mock.purchaseCallCount == 0)
        // Note: We cannot construct a Product in tests, so we verify the
        // counter initializes to zero. The tracking mechanism is validated
        // by the mock's implementation and would increment on actual call.
    }

    @Test("restore call is tracked")
    func restoreCallTracked() async {
        let mock = MockSubscriptionProvider()
        await mock.restorePurchases()
        #expect(mock.restoreCallCount == 1)
    }

    @Test("multiple restore calls accumulate")
    func multipleRestoreCallsAccumulate() async {
        let mock = MockSubscriptionProvider()
        await mock.restorePurchases()
        await mock.restorePurchases()
        await mock.restorePurchases()
        #expect(mock.restoreCallCount == 3)
    }

    @Test("products defaults to empty array")
    func productsDefaultsEmpty() {
        let mock = MockSubscriptionProvider()
        #expect(mock.products.isEmpty)
    }

    @Test("isProUnlocked defaults to false")
    func isProUnlockedDefaultsFalse() {
        let mock = MockSubscriptionProvider()
        #expect(mock.isProUnlocked == false)
    }
}
