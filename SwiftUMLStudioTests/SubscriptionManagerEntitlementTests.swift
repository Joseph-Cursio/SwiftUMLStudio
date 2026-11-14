@testable import SwiftUMLStudio
import Testing

@Suite("SubscriptionManager.entitlementResolved")
struct SubscriptionManagerEntitlementTests {

    @Test("real entitlement always unlocks Pro")
    func entitledAlwaysUnlocks() {
        #expect(SubscriptionManager.entitlementResolved(entitled: true, productCount: 0))
        #expect(SubscriptionManager.entitlementResolved(entitled: true, productCount: 2))
    }

    @Test("no entitlement + no products falls back to unlocked (development)")
    func devFallback() {
        #expect(SubscriptionManager.entitlementResolved(entitled: false, productCount: 0))
    }

    @Test("no entitlement + at least one product keeps Pro locked")
    func productionLocksWithoutEntitlement() {
        #expect(SubscriptionManager.entitlementResolved(entitled: false, productCount: 1) == false)
        #expect(SubscriptionManager.entitlementResolved(entitled: false, productCount: 2) == false)
    }

    @Test("known product identifiers are stable")
    func productIdentifiers() {
        #expect(SubscriptionManager.proMonthlyID == "pro_monthly")
        #expect(SubscriptionManager.proAnnualID == "pro_annual")
    }
}
