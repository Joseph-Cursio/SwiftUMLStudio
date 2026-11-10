import SwiftUI
import SwiftUMLBridgeFramework

// MARK: - Detail Pane

struct DiagramDetailView: View {
    @Bindable var viewModel: DiagramViewModel
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @State private var selectedTab: DetailTab = .preview
    @State private var showPaywall = false

    enum DetailTab: String, CaseIterable {
        case dashboard = "Dashboard"
        case preview = "Preview"
        case markup = "Markup"
    }

    var body: some View {
        VStack(spacing: 0) {
            DiagramInspectorStrip(viewModel: viewModel)

            TabView(selection: $selectedTab) {
                Tab("Dashboard", systemImage: "chart.bar", value: DetailTab.dashboard) {
                    ProjectDashboardView(
                        summary: viewModel.projectSummary,
                        insights: viewModel.insights,
                        suggestions: viewModel.suggestions,
                        architectureDiff: viewModel.architectureDiff,
                        isProUnlocked: subscriptionManager.isProUnlocked,
                        onSuggestionTap: handleSuggestion
                    )
                }

                Tab("Preview", systemImage: "eye", value: DetailTab.preview) {
                    DiagramPreviewView(viewModel: viewModel)
                }

                Tab("Markup", systemImage: "chevron.left.forwardslash.chevron.right", value: DetailTab.markup) {
                    MarkupView(viewModel: viewModel)
                }
            }
            .accessibilityIdentifier("detailTabs")
        }
        .paywallSheet(isPresented: $showPaywall, subscriptionManager: subscriptionManager)
    }

    private func handleSuggestion(_ suggestion: DiagramSuggestion) {
        if SuggestionHandler.handle(suggestion, viewModel: viewModel, subscriptionManager: subscriptionManager) {
            showPaywall = true
        } else {
            selectedTab = .preview
        }
    }
}
