import Foundation
@testable import SwiftUMLStudio

/// Consent stores backed by a throwaway `UserDefaults` suite.
///
/// The unit tests run inside the app and share its defaults, so a test that used
/// ``PlantUMLConsent/shared`` would read — or change — the developer's own decision.
@MainActor
enum PlantUMLConsentTestSupport {

    /// A store holding `decision`, and the suite to remove when the test ends.
    static func makeConsent(
        _ decision: PlantUMLConsent.Decision = .undecided
    ) -> (consent: PlantUMLConsent, suiteName: String) {
        let suiteName = "test-plantuml-consent-\(UUID().uuidString)"
        let consent = PlantUMLConsent(defaults: UserDefaults(suiteName: suiteName)!)
        switch decision {
        case .granted: consent.grant()
        case .declined: consent.decline()
        case .undecided: break
        }
        return (consent, suiteName)
    }
}
