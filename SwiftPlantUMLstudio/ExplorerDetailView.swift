import SwiftUI

struct ExplorerDetailView: View {
    let viewModel: DiagramViewModel

    var body: some View {
        Group {
            if viewModel.currentScript != nil || viewModel.isGenerating {
                DiagramPreviewView(viewModel: viewModel)
            } else {
                ProjectDashboardView(
                    summary: viewModel.projectSummary,
                    insights: viewModel.insights,
                    suggestions: viewModel.suggestions,
                    onSuggestionTap: { _ in }
                )
            }
        }
    }
}
