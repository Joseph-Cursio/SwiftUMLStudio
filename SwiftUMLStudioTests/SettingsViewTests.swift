import Foundation
import SwiftUI
import Testing
import ViewInspector
@testable import SwiftUMLStudio

@Suite("SettingsView")
@MainActor
struct SettingsViewTests {

    private func consentToggle(_ consent: PlantUMLConsent) throws -> InspectableView<ViewType.Toggle> {
        try SettingsView(consent: consent).inspect()
            .find(viewWithAccessibilityIdentifier: "plantUMLConsentToggle").toggle()
    }

    @Test("the PlantUML toggle is on only for a grant", arguments: PlantUMLConsent.Decision.allCases)
    func toggleShowsDecision(_ decision: PlantUMLConsent.Decision) throws {
        let consent = PlantUMLConsentTestSupport.makeConsent(decision)
        #expect(try consentToggle(consent).isOn() == (decision == .granted))
    }

    @Test("turning the toggle on grants consent, from undecided or declined", arguments: [
        PlantUMLConsent.Decision.undecided, .declined
    ])
    func turningOnGrants(_ decision: PlantUMLConsent.Decision) throws {
        let consent = PlantUMLConsentTestSupport.makeConsent(decision)
        try consentToggle(consent).tap()
        #expect(consent.decision == .granted)
    }

    @Test("turning the toggle off revokes consent, so the next preview asks again")
    func turningOffRevokes() throws {
        let consent = PlantUMLConsentTestSupport.makeConsent(.granted)
        try consentToggle(consent).tap()
        #expect(consent.decision == .undecided)
    }
}
