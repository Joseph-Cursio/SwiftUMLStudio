import Foundation

enum ProFeature: String, CaseIterable {
    case sequenceDiagrams
    case dependencyGraphs
    case exportMarkup
    case formatSelection
    case unlimitedProjects
    case architectureTracking
}

@MainActor
enum FeatureGate {
    static func isUnlocked(_ feature: ProFeature, manager: some SubscriptionProviding) -> Bool {
        manager.isProUnlocked
    }
}
