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
        selectedTab = .preview
    }
}

struct DiagramPreviewView: View {
    let viewModel: DiagramViewModel

    var body: some View {
        VStack(spacing: 0) {
            if let model = lowConfidenceModel {
                StateMachineConfidenceBanner(model: model)
            }
            Group {
                if viewModel.isGenerating {
                    ProgressView("Generating…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let script = viewModel.currentScript {
                    if script.format == .svg, let graph = script.layoutGraph {
                        NativeDiagramView(graph: graph)
                    } else if script.format == .svg, let seqLayout = script.sequenceLayout {
                        NativeSequenceDiagramView(layout: seqLayout)
                    } else if script.format == .svg, let activityLayout = script.activityLayout {
                        NativeActivityDiagramView(layout: activityLayout)
                    } else {
                        DiagramWebView(script: script)
                    }
                } else if (viewModel.diagramMode == .sequenceDiagram
                    || viewModel.diagramMode == .activityDiagram)
                    && viewModel.entryPoint.isEmpty {
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

    private var lowConfidenceModel: StateMachineModel? {
        DiagramPreviewView.lowConfidenceModel(
            diagramMode: viewModel.diagramMode,
            stateMachineModel: viewModel.currentStateMachineModel
        )
    }

    /// Returns the state machine model that should drive the confidence banner,
    /// or `nil` when the banner should stay hidden. Exposed for testing.
    static func lowConfidenceModel(
        diagramMode: DiagramMode,
        stateMachineModel: StateMachineModel?
    ) -> StateMachineModel? {
        guard diagramMode == .stateMachine,
              let model = stateMachineModel,
              model.confidence != .high
        else { return nil }
        return model
    }
}

struct StateMachineConfidenceBanner: View {
    let model: StateMachineModel

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(headline).font(.subheadline.bold())
                ForEach(model.notes, id: \.self) { note in
                    Text("• \(note)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(tint.opacity(0.1))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(tint.opacity(0.3)), alignment: .bottom)
        .accessibilityIdentifier("stateMachineConfidenceBanner")
    }

    var symbol: String {
        model.confidence == .medium ? "info.circle.fill" : "exclamationmark.triangle.fill"
    }

    var tint: SwiftUI.Color {
        model.confidence == .medium ? .orange : .red
    }

    var headline: String {
        switch model.confidence {
        case .medium: return "Partially inferred state machine"
        case .low: return "Low-confidence state machine"
        case .high: return ""
        }
    }
}
