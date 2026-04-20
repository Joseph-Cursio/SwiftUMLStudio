import Foundation
import Testing
@testable import SwiftUMLStudio

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

@Suite("PaywallFeature.all")
struct PaywallFeatureTests {

    @Test("five Pro features are advertised")
    func count() {
        #expect(PaywallFeature.all.count == 5)
    }

    @Test("each feature has a non-empty title and description")
    func nonEmptyContent() {
        for feature in PaywallFeature.all {
            #expect(feature.title.isEmpty == false)
            #expect(feature.description.isEmpty == false)
        }
    }

    @Test("titles cover the expected Pro areas")
    func coversProAreas() {
        let titles = Set(PaywallFeature.all.map(\.title))
        #expect(titles.contains("Sequence Diagrams"))
        #expect(titles.contains("Dependency Graphs"))
        #expect(titles.contains("PlantUML & Mermaid Export"))
    }

    @Test("each feature identifier is unique")
    func uniqueIdentifiers() {
        let identifiers = Set(PaywallFeature.all.map(\.id))
        #expect(identifiers.count == PaywallFeature.all.count)
    }
}
