enum ProFeature: String, CaseIterable {
    case sequenceDiagrams
    case dependencyGraphs
    case stateMachines
    case activityDiagrams
    case erDiagrams
    case componentDiagrams
    case exportMarkup
    case formatSelection
    case unlimitedProjects
    case architectureTracking
}

@MainActor
enum FeatureGate {
    static func isUnlocked(_: ProFeature, manager: some SubscriptionProviding) -> Bool {
        manager.isProUnlocked
    }
}
