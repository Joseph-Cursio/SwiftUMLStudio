import Foundation
import Testing
@testable import SwiftUMLStudio

// MARK: - GCD dispatch helpers

private func runOnMain(_ block: @MainActor () -> Void) {
    if Thread.isMainThread {
        MainActor.assumeIsolated(block)
    } else {
        DispatchQueue.main.sync { MainActor.assumeIsolated(block) }
    }
}

// MARK: - ProFeature Tests

struct ProFeatureTests {

    @Test("has eight cases")
    func allCasesCount() {
        #expect(ProFeature.allCases.count == 8)
    }

    @Test("includes expected features")
    func expectedCases() {
        let cases = Set(ProFeature.allCases)
        #expect(cases.contains(.sequenceDiagrams))
        #expect(cases.contains(.dependencyGraphs))
        #expect(cases.contains(.stateMachines))
        #expect(cases.contains(.activityDiagrams))
        #expect(cases.contains(.exportMarkup))
        #expect(cases.contains(.formatSelection))
        #expect(cases.contains(.unlimitedProjects))
        #expect(cases.contains(.architectureTracking))
    }
}

// MARK: - FeatureGate Tests

struct FeatureGateTests {

    @Test("all features unlocked when Pro is active")
    func proUnlockedAllFeatures() {
        runOnMain {
            let manager = SubscriptionManager()
            for feature in ProFeature.allCases {
                #expect(FeatureGate.isUnlocked(feature, manager: manager))
            }
        }
    }
}
