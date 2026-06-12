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
        .paywallSheet(isPresented: $showPaywall, subscriptionManager: subscriptionManager)
    }

    private func handleSuggestion(_ suggestion: DiagramSuggestion) {
        if SuggestionHandler.handle(suggestion, viewModel: viewModel, subscriptionManager: subscriptionManager) {
            showPaywall = true
        }
    }
}
