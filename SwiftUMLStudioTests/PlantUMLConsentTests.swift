import Foundation
import Testing
@testable import SwiftUMLStudio

// Each test keeps its store in memory, so they run in parallel and never touch
// `UserDefaults.standard`, which in this app-hosted bundle is the developer's
// real app defaults — or leave a suite's plist behind in ~/Library/Preferences.
@Suite("PlantUMLConsent")
@MainActor
struct PlantUMLConsentTests {

    @Test("a fresh store is undecided")
    func freshStoreIsUndecided() {
        let consent = PlantUMLConsentTestSupport.makeConsent()
        #expect(consent.decision == .undecided)
        #expect(consent.isGranted == false)
    }

    @Test("each decision is stored and read back by a new store", arguments: PlantUMLConsent.Decision.allCases)
    func decisionPersists(_ decision: PlantUMLConsent.Decision) {
        let storage = InMemoryKeyValueStore()
        let consent = PlantUMLConsentTestSupport.makeConsent(decision, storage: storage)
        #expect(consent.decision == decision)
        #expect(PlantUMLConsent(defaults: storage).decision == decision)
    }

    @Test("a later decision replaces an earlier one, in memory and in storage")
    func laterDecisionReplacesEarlier() {
        let storage = InMemoryKeyValueStore()
        let consent = PlantUMLConsentTestSupport.makeConsent(.granted, storage: storage)

        // A new store reads what is stored; a stale key left behind would win over the new one.
        consent.decline()
        #expect(consent.decision == .declined)
        #expect(PlantUMLConsent(defaults: storage).decision == .declined)
        consent.grant()
        #expect(consent.decision == .granted)
        #expect(PlantUMLConsent(defaults: storage).decision == .granted)
        consent.revoke()
        #expect(consent.decision == .undecided)
        #expect(PlantUMLConsent(defaults: storage).decision == .undecided)
    }

    @Test("a grant stored under the original key still counts")
    func legacyGrantCounts() {
        let storage = InMemoryKeyValueStore()
        storage.set(true, forKey: "plantUMLRenderingConsented")
        #expect(PlantUMLConsent(defaults: storage).decision == .granted)
    }

    @Test("recording a decision leaves the app's own defaults alone")
    func leavesStandardDefaultsAlone() {
        func standardKeys() -> [Bool?] {
            [PlantUMLConsent.grantedKey, PlantUMLConsent.declinedKey].map {
                UserDefaults.standard.object(forKey: $0) as? Bool
            }
        }
        let before = standardKeys()
        let consent = PlantUMLConsentTestSupport.makeConsent()

        // A grant and a decline leave different footprints, so a store that also wrote to
        // .standard would change one of these whatever the developer's own decision is.
        consent.grant()
        #expect(standardKeys() == before)
        consent.decline()
        #expect(standardKeys() == before)
    }
}
