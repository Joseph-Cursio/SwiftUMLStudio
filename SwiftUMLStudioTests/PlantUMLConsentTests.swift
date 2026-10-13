import Foundation
import Testing
@testable import SwiftUMLStudio

// Each test uses its own suite, so they run in parallel and never touch
// `UserDefaults.standard`, which in this app-hosted bundle is the developer's
// real app defaults.
@Suite("PlantUMLConsent")
@MainActor
struct PlantUMLConsentTests {

    @Test("a fresh store is undecided")
    func freshStoreIsUndecided() {
        let (consent, suiteName) = PlantUMLConsentTestSupport.makeConsent()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        #expect(consent.decision == .undecided)
        #expect(consent.isGranted == false)
    }

    @Test("each decision is stored and read back by a new store", arguments: PlantUMLConsent.Decision.allCases)
    func decisionPersists(_ decision: PlantUMLConsent.Decision) throws {
        let (consent, suiteName) = PlantUMLConsentTestSupport.makeConsent(decision)
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        #expect(consent.decision == decision)
        let reopened = PlantUMLConsent(defaults: try #require(UserDefaults(suiteName: suiteName)))
        #expect(reopened.decision == decision)
    }

    @Test("a later decision replaces an earlier one")
    func laterDecisionReplacesEarlier() {
        let (consent, suiteName) = PlantUMLConsentTestSupport.makeConsent(.granted)
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        consent.decline()
        #expect(consent.decision == .declined)
        consent.grant()
        #expect(consent.decision == .granted)
        consent.revoke()
        #expect(consent.decision == .undecided)
    }

    @Test("a grant stored under the original key still counts")
    func legacyGrantCounts() throws {
        let suiteName = "test-plantuml-consent-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.set(true, forKey: "plantUMLRenderingConsented")
        #expect(PlantUMLConsent(defaults: defaults).decision == .granted)
    }

    @Test("recording a decision leaves the app's own defaults alone")
    func leavesStandardDefaultsAlone() {
        let before = UserDefaults.standard.object(forKey: PlantUMLConsent.grantedKey) as? Bool
        let (consent, suiteName) = PlantUMLConsentTestSupport.makeConsent(.granted)
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        consent.revoke()
        consent.decline()
        #expect(UserDefaults.standard.object(forKey: PlantUMLConsent.grantedKey) as? Bool == before)
    }
}
