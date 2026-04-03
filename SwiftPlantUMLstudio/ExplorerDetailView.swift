import SwiftUI

struct ExplorerDetailView: View {
    let viewModel: DiagramViewModel
    @Environment(SubscriptionManager.self) private var subscriptionManager

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
                    onSuggestionTap: { _ in }
                )
            }
        }
    }
}
