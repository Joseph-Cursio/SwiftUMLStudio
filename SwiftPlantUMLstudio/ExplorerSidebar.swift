import SwiftUI
import SwiftUMLBridgeFramework

struct ExplorerSidebar: View {
    @Bindable var viewModel: DiagramViewModel
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @State private var showPaywall = false

    var body: some View {
        List {
            if viewModel.insights.isEmpty && viewModel.suggestions.isEmpty {
                Section {
                    ContentUnavailableView(
                        "Open a project",
                        systemImage: "folder",
                        description: Text("Drop a folder to see insights and suggestions.")
                    )
                }
            } else {
                if viewModel.insights.isEmpty == false {
                    Section("Insights") {
                        ForEach(viewModel.insights) { insight in
                            InsightRowView(insight: insight)
                        }
                    }
                }

                if viewModel.suggestions.isEmpty == false {
                    Section("Suggested Diagrams") {
                        ForEach(viewModel.suggestions) { suggestion in
                            SuggestionCardView(
                                suggestion: suggestion,
                                onTap: handleSuggestion
                            )
                        }
                    }
                }
            }

            Section("History") {
                if viewModel.history.isEmpty {
                    ContentUnavailableView("No history yet", systemImage: "clock")
                } else {
                    ForEach(viewModel.history) { item in
                        ContentView.HistoryItemRow(item: item)
                            .tag(item)
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    viewModel.deleteHistoryItem(item)
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle("SwiftUML Explorer")
        .sheet(isPresented: $showPaywall) {
            PaywallView(subscriptionManager: subscriptionManager)
        }
    }

    private func handleSuggestion(_ suggestion: DiagramSuggestion) {
        if suggestion.requiresPro
            && !FeatureGate.isUnlocked(.sequenceDiagrams, manager: subscriptionManager) {
            showPaywall = true
            return
        }
        switch suggestion.action {
        case .classDiagram:
            viewModel.diagramMode = .classDiagram
        case .sequenceDiagram(let entryPoint):
            viewModel.diagramMode = .sequenceDiagram
            viewModel.entryPoint = entryPoint
        case .dependencyGraph(let mode):
            viewModel.diagramMode = .dependencyGraph
            viewModel.depsMode = mode
        }
        viewModel.generate()
    }
}
