import Foundation
import Observation
import StoreKit
@testable import SwiftUMLStudio
import Testing

// MARK: - FeatureGate + Mock Tests

@Suite("FeatureGate with MockSubscriptionProvider") @MainActor
struct FeatureGateMockTests {

    @Test("all features locked when Pro is not unlocked",
          arguments: ProFeature.allCases)
    func featureLockedWhenProLocked(feature: ProFeature) {
        let mock = MockSubscriptionProvider()
        mock.isProUnlocked = false
        #expect(FeatureGate.isUnlocked(feature, manager: mock) == false)
    }

    @Test("all features unlocked when Pro is active",
          arguments: ProFeature.allCases)
    func featureUnlockedWhenProActive(feature: ProFeature) {
        let mock = MockSubscriptionProvider()
        mock.isProUnlocked = true
        #expect(FeatureGate.isUnlocked(feature, manager: mock))
    }

    @Test("toggling Pro state changes gate result")
    func togglingProStateChangesGateResult() {
        let mock = MockSubscriptionProvider()
        mock.isProUnlocked = false
        #expect(FeatureGate.isUnlocked(.sequenceDiagrams, manager: mock) == false)

        mock.isProUnlocked = true
        #expect(FeatureGate.isUnlocked(.sequenceDiagrams, manager: mock))
    }
}
