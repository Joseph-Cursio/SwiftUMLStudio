import Foundation
@testable import SwiftUMLStudio

/// Consent stores kept in memory.
///
/// The unit tests run inside the app and share its defaults, so a test that used
/// ``PlantUMLConsent/shared`` would read — or change — the developer's own decision.
/// A throwaway `UserDefaults` suite avoids that but leaves an empty plist in
/// `~/Library/Preferences` on every run, so these never reach `UserDefaults` at all.
@MainActor
enum PlantUMLConsentTestSupport {

    /// A store holding `decision`, kept in `storage`.
    static func makeConsent(
        _ decision: PlantUMLConsent.Decision = .undecided,
        storage: any KeyValueStore = InMemoryKeyValueStore()
    ) -> PlantUMLConsent {
        let consent = PlantUMLConsent(defaults: storage)
        switch decision {
        case .granted: consent.grant()
        case .declined: consent.decline()
        case .undecided: break
        }
        return consent
    }
}
