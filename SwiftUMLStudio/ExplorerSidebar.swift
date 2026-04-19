import SwiftUI
import SwiftUMLBridgeFramework

struct ExplorerSidebar: View {
    @Bindable var viewModel: DiagramViewModel
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @State private var showPaywall = false
    @State private var reminderEnabled = ReviewReminderManager.isEnabled()

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

            if subscriptionManager.isProUnlocked {
                if !viewModel.snapshots.isEmpty {
                    Section("Architecture Snapshots") {
                        ForEach(viewModel.snapshots) { snapshot in
                            SnapshotRowView(snapshot: snapshot)
                                .contextMenu {
                                    Button("Delete", role: .destructive) {
                                        viewModel.deleteSnapshot(snapshot)
                                    }
                                }
                        }
                    }
                }

                Section("Review Reminders") {
                    Toggle("Remind me to review", isOn: $reminderEnabled)
                        .onChange(of: reminderEnabled) {
                            if reminderEnabled {
                                ReviewReminderManager.enableReminder()
                            } else {
                                ReviewReminderManager.disableReminder()
                            }
                        }
                    if reminderEnabled {
                        Text("You'll be reminded every 2 weeks if you haven't reviewed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("History") {
                if viewModel.history.isEmpty {
                    ContentUnavailableView("No history yet", systemImage: "clock")
                } else {
                    ForEach(viewModel.history) { item in
                        HistoryItemRow(item: item)
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
