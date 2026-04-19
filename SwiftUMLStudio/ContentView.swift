import SwiftUI
import SwiftUMLBridgeFramework
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @State private var viewModel = DiagramViewModel()
    @State private var showPaywall = false
    @AppStorage("appMode") private var appMode: AppMode = .explorer

    var body: some View {
        Group {
            switch appMode {
            case .explorer:
                explorerLayout
            case .developer:
                developerLayout
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFile)) { _ in
            openPanel()
        }
        .task {
            viewModel.loadHistory()
            viewModel.loadSnapshots()
            loadTestFixtureIfNeeded()
        }
        .onChange(of: viewModel.selectedPaths) {
            viewModel.rebuildFileTree()
            viewModel.generate()
            viewModel.analyzeProject(isProUnlocked: subscriptionManager.isProUnlocked)
            if viewModel.diagramMode == .sequenceDiagram {
                viewModel.refreshEntryPoints()
            }
        }
        .onChange(of: viewModel.selectedFileURL) {
            viewModel.selectFile(viewModel.selectedFileURL)
        }
        .onChange(of: viewModel.diagramMode) {
            if viewModel.diagramMode == .sequenceDiagram
                && !FeatureGate.isUnlocked(.sequenceDiagrams, manager: subscriptionManager) {
                viewModel.diagramMode = .classDiagram
                showPaywall = true
                return
            }
            if viewModel.diagramMode == .dependencyGraph
                && !FeatureGate.isUnlocked(.dependencyGraphs, manager: subscriptionManager) {
                viewModel.diagramMode = .classDiagram
                showPaywall = true
                return
            }
            viewModel.generate()
            if viewModel.diagramMode == .sequenceDiagram && !viewModel.selectedPaths.isEmpty {
                viewModel.refreshEntryPoints()
            }
        }
        .onChange(of: viewModel.diagramFormat) { viewModel.generate() }
        .onChange(of: viewModel.entryPoint) { viewModel.generate() }
        .onChange(of: viewModel.sequenceDepth) { viewModel.generate() }
        .onChange(of: viewModel.depsMode) { viewModel.generate() }
        .sheet(isPresented: $showPaywall) {
            PaywallView(subscriptionManager: subscriptionManager)
        }
    }

    // MARK: - Explorer Layout

    private var explorerLayout: some View {
        NavigationSplitView {
            ExplorerSidebar(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 250, ideal: 320)
        } detail: {
            ExplorerDetailView(viewModel: viewModel)
        }
        .frame(minWidth: 900)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ExplorerToolbar(
                    pathSummary: viewModel.pathSummary,
                    appMode: $appMode,
                    onOpen: openPanel,
                    onSave: { viewModel.save(isProUnlocked: subscriptionManager.isProUnlocked) },
                    saveDisabled: viewModel.currentScript == nil || viewModel.isGenerating
                )
            }
        }
    }

    // MARK: - Developer Layout

    private var developerLayout: some View {
        @Bindable var bindableVM = viewModel

        return NavigationSplitView {
            VStack(spacing: 0) {
                FileBrowserSidebar(viewModel: viewModel)
                Divider()
                HistorySidebar(viewModel: viewModel)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 250)
        } content: {
            SourceEditorView(
                content: viewModel.selectedFileContent,
                hasSelection: viewModel.selectedFileURL != nil
            )
            .navigationSplitViewColumnWidth(min: 300, ideal: 400)
            .navigationTitle(viewModel.selectedFileURL?.lastPathComponent ?? "Source")
        } detail: {
            DiagramDetailView(viewModel: viewModel)
        }
        .frame(minWidth: 1400)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Open…", systemImage: "folder", action: openPanel)
                    .help("Open Swift files or directories (⌘O)")

                Text(viewModel.pathSummary)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 300, alignment: .leading)

                Picker("Mode", selection: $bindableVM.diagramMode) {
                    ForEach(DiagramMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 360)
                .accessibilityIdentifier("modePicker")

                Picker("Format", selection: $bindableVM.diagramFormat) {
                    Text("PlantUML").tag(DiagramFormat.plantuml)
                    Text("Mermaid").tag(DiagramFormat.mermaid)
                    Text("Nomnoml").tag(DiagramFormat.nomnoml)
                    Text("SVG").tag(DiagramFormat.svg)
                }
                .pickerStyle(.menu)
                .frame(width: 120)

                if viewModel.diagramMode == .sequenceDiagram {
                    SequenceControlsView(viewModel: viewModel)
                }

                if viewModel.diagramMode == .dependencyGraph {
                    Picker("Deps Mode", selection: $bindableVM.depsMode) {
                        ForEach(DepsMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                    .accessibilityIdentifier("depsModeControl")
                }

                Picker("App Mode", selection: $appMode) {
                    ForEach(AppMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                .accessibilityIdentifier("appModePicker")

                Button("Save", systemImage: "square.and.arrow.down") {
                    viewModel.save(isProUnlocked: subscriptionManager.isProUnlocked)
                }
                .keyboardShortcut("s", modifiers: .command)
                .help("Save to history (⌘S)")
                .disabled(viewModel.currentScript == nil || viewModel.isGenerating)
            }
        }
    }

    // MARK: - Logic

    /// Checks for a `-testFixturePath` launch argument and pre-loads it.
    private func loadTestFixtureIfNeeded() {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-testFixturePath"),
              idx + 1 < args.count else { return }
        let path = args[idx + 1]
        viewModel.selectedPaths = [path]
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.swiftSource]
        panel.canSelectHiddenExtension = true

        guard panel.runModal() == .OK else { return }
        viewModel.selectedPaths = panel.urls.map { $0.path() }
        viewModel.generate()
    }
}

extension Notification.Name {
    static let openFile = Notification.Name("openFile")
}

#Preview {
    ContentView()
        .environment(SubscriptionManager())
}
