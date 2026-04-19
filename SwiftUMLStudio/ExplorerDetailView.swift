import SwiftUI

struct ExplorerDetailView: View {
    let viewModel: DiagramViewModel
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @State private var showPaywall = false

    var body: some View {
        Group {
            if viewModel.currentScript != nil || viewModel.isGenerating {
                DiagramPreviewView(viewModel: viewModel)
            } else {
                ProjectDashboardView(
                    summary: viewModel.projectSummary,
                    insights: viewModel.insights,
                    suggestions: viewModel.suggestions,
                    architectureDiff: viewModel.architectureDiff,
                    isProUnlocked: subscriptionManager.isProUnlocked,
                    onSuggestionTap: handleSuggestion
                )
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(subscriptionManager: subscriptionManager)
        }
    }

    private func handleSuggestion(_ suggestion: DiagramSuggestion) {
        if suggestion.requiresPro {
            let feature = SuggestionDispatcher.featureRequired(for: suggestion.action)
            guard FeatureGate.isUnlocked(feature, manager: subscriptionManager) else {
                showPaywall = true
                return
            }
        }
        SuggestionDispatcher.apply(suggestion, to: viewModel)
        viewModel.generate()
    }
}
