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
        TabView(selection: $selectedTab) {
            ProjectDashboardView(
                summary: viewModel.projectSummary,
                insights: viewModel.insights,
                suggestions: viewModel.suggestions,
                onSuggestionTap: handleSuggestion
            )
            .tabItem { Label("Dashboard", systemImage: "chart.bar") }
            .tag(DetailTab.dashboard)

            DiagramPreviewView(viewModel: viewModel)
                .tabItem { Label("Preview", systemImage: "eye") }
                .tag(DetailTab.preview)

            MarkupView(viewModel: viewModel)
                .tabItem { Label("Markup", systemImage: "chevron.left.forwardslash.chevron.right") }
                .tag(DetailTab.markup)
        }
        .accessibilityIdentifier("detailTabs")
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
        selectedTab = .preview
    }
}

struct DiagramPreviewView: View {
    let viewModel: DiagramViewModel

    var body: some View {
        Group {
            if viewModel.isGenerating {
                ProgressView("Generating…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.currentScript != nil {
                DiagramWebView(script: viewModel.currentScript)
            } else if viewModel.diagramMode == .sequenceDiagram && viewModel.entryPoint.isEmpty {
                Text("Enter an entry point (e.g. MyType.myMethod) to generate a diagram.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("entryPointPrompt")
            } else {
                Text("Select Swift source files or a folder to generate a diagram.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("fileSelectionPrompt")
            }
        }
    }
}

struct MarkupView: View {
    let viewModel: DiagramViewModel

    var body: some View {
        Group {
            if let script = viewModel.currentScript {
                TextEditor(text: .constant(script.text))
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.background)
                    .disabled(true)
            } else {
                ContentUnavailableView("No diagram generated", systemImage: "doc.text")
            }
        }
    }
}
