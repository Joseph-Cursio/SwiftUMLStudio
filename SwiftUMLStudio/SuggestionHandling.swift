import SwiftUI

/// Shared dispatch for a tapped `DiagramSuggestion`, used by the Explorer and
/// developer detail views.
enum SuggestionHandler {
    /// Apply `suggestion` and regenerate, unless it is pro-gated while the user
    /// is locked out. Returns `true` when a paywall should be shown instead
    /// (nothing was applied); `false` when the suggestion was applied.
    static func handle(
        _ suggestion: DiagramSuggestion,
        viewModel: DiagramViewModel,
        subscriptionManager: SubscriptionManager
    ) -> Bool {
        if suggestion.requiresPro {
            let feature = SuggestionDispatcher.featureRequired(for: suggestion.action)
            guard FeatureGate.isUnlocked(feature, manager: subscriptionManager) else {
                return true
            }
        }
        SuggestionDispatcher.apply(suggestion, to: viewModel)
        viewModel.generate()
        return false
    }
}

extension View {
    /// Presents the StoreKit paywall sheet shared by the suggestion-handling views.
    func paywallSheet(
        isPresented: Binding<Bool>,
        subscriptionManager: SubscriptionManager
    ) -> some View {
        sheet(isPresented: isPresented) {
            PaywallView(subscriptionManager: subscriptionManager)
        }
    }
}
