import Foundation
import Observation
import os
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

    @Test("a later decision replaces an earlier one, in memory and in storage")
    func laterDecisionReplacesEarlier() throws {
        let (consent, suiteName) = PlantUMLConsentTestSupport.makeConsent(.granted)
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let defaults = try #require(UserDefaults(suiteName: suiteName))

        // A new store reads what is stored; a stale key left behind would win over the new one.
        consent.decline()
        #expect(consent.decision == .declined)
        #expect(PlantUMLConsent(defaults: defaults).decision == .declined)
        consent.grant()
        #expect(consent.decision == .granted)
        #expect(PlantUMLConsent(defaults: defaults).decision == .granted)
        consent.revoke()
        #expect(consent.decision == .undecided)
        #expect(PlantUMLConsent(defaults: defaults).decision == .undecided)
    }

    @Test("a change of decision notifies observers, so open previews and Settings update at once")
    func changeNotifiesObservers() {
        let (consent, suiteName) = PlantUMLConsentTestSupport.makeConsent(.granted)
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let changed = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            _ = consent.isGranted
        } onChange: {
            changed.withLock { $0 = true }
        }

        consent.revoke()

        #expect(changed.withLock { $0 })
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
        func standardKeys() -> [Bool?] {
            [PlantUMLConsent.grantedKey, PlantUMLConsent.declinedKey].map {
                UserDefaults.standard.object(forKey: $0) as? Bool
            }
        }
        let before = standardKeys()
        let (consent, suiteName) = PlantUMLConsentTestSupport.makeConsent()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        // A grant and a decline leave different footprints, so a store that also wrote to
        // .standard would change one of these whatever the developer's own decision is.
        consent.grant()
        #expect(standardKeys() == before)
        consent.decline()
        #expect(standardKeys() == before)
    }
}
