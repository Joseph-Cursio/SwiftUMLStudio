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
    @State private var viewport = DiagramViewport()

    var body: some View {
        VStack(spacing: 0) {
            if let model = lowConfidenceModel {
                StateMachineConfidenceBanner(model: model)
            }
            ZStack(alignment: .topTrailing) {
                Group {
                    if viewModel.isGenerating {
                        ProgressView("Generating…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let script = viewModel.currentScript {
                        if script.format == .svg, let graph = script.layoutGraph {
                            cmdScrollHost {
                                NativeDiagramView(graph: graph, viewport: viewport)
                            }
                        } else if script.format == .svg, let seqLayout = script.sequenceLayout {
                            cmdScrollHost {
                                NativeSequenceDiagramView(layout: seqLayout, viewport: viewport)
                            }
                        } else if script.format == .svg, let activityLayout = script.activityLayout {
                            cmdScrollHost {
                                NativeActivityDiagramView(layout: activityLayout, viewport: viewport)
                            }
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
                    } else if viewModel.diagramMode == .componentDiagram
                        && viewModel.packageDescription == nil {
                        Text("Component diagrams require an open Swift Package. Use Open Package… (⇧⌘O) to load a Package.swift directory.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .accessibilityIdentifier("componentPackagePrompt")
                    } else {
                        Text("Select Swift source files or a folder to generate a diagram.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .accessibilityIdentifier("fileSelectionPrompt")
                    }
                }

                if showsExportMenu || showsViewportControls {
                    HStack(spacing: 8) {
                        if showsExportMenu {
                            DiagramExportMenu(viewModel: viewModel, viewport: viewport)
                        }
                        if showsViewportControls {
                            DiagramViewportControls(viewport: viewport)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }

                if let revealable = revealableSelection {
                    revealInSourceButton(for: revealable)
                }

                if let hovered = hoveredInfo {
                    NodeInfoTooltip(
                        label: hovered.label,
                        stereotype: hovered.stereotype,
                        sourceLocation: hovered.sourceLocation
                    )
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .allowsHitTesting(false)
                }
            }
            .onChange(of: viewModel.currentScript?.text) { _, _ in
                viewport.reset()
                viewport.selectedNodeId = nil
                viewport.hoveredNodeId = nil
            }
        }
    }

    private var showsViewportControls: Bool {
        guard let script = viewModel.currentScript, script.format == .svg else { return false }
        return script.layoutGraph != nil
            || script.sequenceLayout != nil
            || script.activityLayout != nil
    }

    /// Show the Export menu whenever a script is present — even WebView-only
    /// formats (PlantUML / Mermaid / Nomnoml) can export their source text.
    private var showsExportMenu: Bool {
        guard let script = viewModel.currentScript else { return false }
        return !script.text.isEmpty
    }

    /// Hosts the given native canvas in a `CommandScrollWrapper` so ⌘+scroll
    /// drives `viewport.zoomIn` / `zoomOut` (other scroll events fall through).
    @ViewBuilder
    private func cmdScrollHost<V: View>(@ViewBuilder _ content: @escaping () -> V) -> some View {
        CommandScrollWrapper(content: content) { deltaY in
            if deltaY > 0 { viewport.zoomIn() }
            else if deltaY < 0 { viewport.zoomOut() }
        }
    }

    /// The currently-selected node (class-diagram LayoutNode or
    /// sequence-diagram participant), paired with its source location when
    /// available. Used to decide whether to surface the "Reveal in Source"
    /// affordance.
    private var revealableSelection: (label: String, location: SourceLocation)? {
        guard let id = viewport.selectedNodeId else { return nil }
        if let graph = viewModel.currentScript?.layoutGraph,
           let node = graph.nodes.first(where: { $0.id == id }),
           let location = node.sourceLocation {
            return (node.label, location)
        }
        if let layout = viewModel.currentScript?.sequenceLayout,
           let participant = layout.participants.first(where: { $0.id == id }),
           let location = participant.sourceLocation {
            return (participant.name, location)
        }
        return nil
    }

    /// Information about whichever class-diagram node or sequence-diagram
    /// participant is under the cursor. Drives the `NodeInfoTooltip` overlay.
    private var hoveredInfo: (label: String, stereotype: String?, sourceLocation: SourceLocation?)? {
        guard let id = viewport.hoveredNodeId else { return nil }
        if let graph = viewModel.currentScript?.layoutGraph,
           let node = graph.nodes.first(where: { $0.id == id }) {
            return (node.label, node.stereotype, node.sourceLocation)
        }
        if let layout = viewModel.currentScript?.sequenceLayout,
           let participant = layout.participants.first(where: { $0.id == id }) {
            return (participant.name, "participant", participant.sourceLocation)
        }
        return nil
    }

    @ViewBuilder
    private func revealInSourceButton(
        for selection: (label: String, location: SourceLocation)
    ) -> some View {
        Button {
            viewModel.revealSource(at: selection.location)
        } label: {
            Label(
                "Reveal \(selection.label) in Source",
                systemImage: "arrow.up.right.square"
            )
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.secondary.opacity(0.2), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .keyboardShortcut("j", modifiers: .command)
        .help("Open the file containing \(selection.label) (⌘J)")
        .accessibilityIdentifier("revealInSourceButton")
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
