import Foundation
import Testing
@testable import SwiftUMLStudio

// MARK: - ProFeature Tests

@MainActor
struct ProFeatureTests {

    @Test("has ten cases")
    func allCasesCount() {
        #expect(ProFeature.allCases.count == 10)
    }

    @Test("includes expected features")
    func expectedCases() {
        let cases = Set(ProFeature.allCases)
        #expect(cases.contains(.sequenceDiagrams))
        #expect(cases.contains(.dependencyGraphs))
        #expect(cases.contains(.stateMachines))
        #expect(cases.contains(.activityDiagrams))
        #expect(cases.contains(.erDiagrams))
        #expect(cases.contains(.componentDiagrams))
        #expect(cases.contains(.exportMarkup))
        #expect(cases.contains(.formatSelection))
        #expect(cases.contains(.unlimitedProjects))
        #expect(cases.contains(.architectureTracking))
    }
}

// MARK: - FeatureGate Tests

@MainActor
struct FeatureGateTests {

    @Test("all features unlocked when Pro is active")
    func proUnlockedAllFeatures() {
        let manager = SubscriptionManager()
        for feature in ProFeature.allCases {
            #expect(FeatureGate.isUnlocked(feature, manager: manager))
        }
    }
}
