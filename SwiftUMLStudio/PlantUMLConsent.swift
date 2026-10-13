import Foundation
import Observation

/// The user's decision about rendering PlantUML diagrams via the third-party
/// `planttext.com` service. PlantUML rendering uploads the diagram source over
/// HTTPS to that service — the consent gate makes the network use explicit
/// instead of silent, which App Store Review expects for any non-essential
/// third-party data transmission.
///
/// Other formats (Mermaid, Nomnoml, SVG) render locally and do not require
/// consent.
///
/// The decision lives in the `UserDefaults` it is built with. The app uses
/// ``shared``; tests build their own from a throwaway suite, because the unit
/// tests run inside the app and share its defaults — a test that revoked
/// consent through `UserDefaults.standard` cleared the developer's own.
@Observable
final class PlantUMLConsent {
    enum Decision: CaseIterable {
        case undecided
        case granted
        case declined
    }

    static let shared = PlantUMLConsent(defaults: .standard)

    /// The key a grant has always been stored under, so a grant given before
    /// the store existed still counts.
    nonisolated static let grantedKey = "plantUMLRenderingConsented"
    nonisolated static let declinedKey = "plantUMLRenderingDeclined"

    @ObservationIgnored private let defaults: UserDefaults
    private(set) var decision: Decision

    init(defaults: UserDefaults) {
        self.defaults = defaults
        if defaults.bool(forKey: Self.grantedKey) {
            decision = .granted
        } else if defaults.bool(forKey: Self.declinedKey) {
            decision = .declined
        } else {
            decision = .undecided
        }
    }

    var isGranted: Bool { decision == .granted }

    func grant() { record(.granted) }

    func decline() { record(.declined) }

    /// Back to undecided — used by tests and any future Settings surface that
    /// offers a "revoke" toggle.
    func revoke() { record(.undecided) }

    private func record(_ newDecision: Decision) {
        defaults.removeObject(forKey: Self.grantedKey)
        defaults.removeObject(forKey: Self.declinedKey)
        switch newDecision {
        case .granted: defaults.set(true, forKey: Self.grantedKey)
        case .declined: defaults.set(true, forKey: Self.declinedKey)
        case .undecided: break
        }
        decision = newDecision
    }
}
