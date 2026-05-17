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
            if viewModel.diagramMode == .sequenceDiagram
                || viewModel.diagramMode == .activityDiagram {
                viewModel.refreshEntryPoints()
            } else if viewModel.diagramMode == .stateMachine {
                viewModel.refreshStateMachines()
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
            if viewModel.diagramMode == .stateMachine
                && !FeatureGate.isUnlocked(.stateMachines, manager: subscriptionManager) {
                viewModel.diagramMode = .classDiagram
                showPaywall = true
                return
            }
            if viewModel.diagramMode == .activityDiagram
                && !FeatureGate.isUnlocked(.activityDiagrams, manager: subscriptionManager) {
                viewModel.diagramMode = .classDiagram
                showPaywall = true
                return
            }
            if viewModel.diagramMode == .erDiagram
                && !FeatureGate.isUnlocked(.erDiagrams, manager: subscriptionManager) {
                viewModel.diagramMode = .classDiagram
                showPaywall = true
                return
            }
            if viewModel.diagramMode == .componentDiagram
                && !FeatureGate.isUnlocked(.componentDiagrams, manager: subscriptionManager) {
                viewModel.diagramMode = .classDiagram
                showPaywall = true
                return
            }
            viewModel.generate()
            if (viewModel.diagramMode == .sequenceDiagram
                || viewModel.diagramMode == .activityDiagram)
                && !viewModel.selectedPaths.isEmpty {
                viewModel.refreshEntryPoints()
            } else if viewModel.diagramMode == .stateMachine && !viewModel.selectedPaths.isEmpty {
                viewModel.refreshStateMachines()
            }
        }
        .onChange(of: viewModel.diagramFormat) { viewModel.generate() }
        .onChange(of: viewModel.entryPoint) { viewModel.generate() }
        .onChange(of: viewModel.sequenceDepth) { viewModel.generate() }
        .onChange(of: viewModel.depsMode) { viewModel.generate() }
        .onChange(of: viewModel.stateIdentifier) { viewModel.generate() }
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
        NavigationSplitView {
            WorkspaceSidebar(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 200, ideal: 250)
        } content: {
            SourceEditorView(
                content: viewModel.selectedFileContent,
                hasSelection: viewModel.selectedFileURL != nil,
                highlightedLine: viewModel.highlightedSourceLine
            )
            .navigationSplitViewColumnWidth(min: 300, ideal: 400)
            .navigationTitle(viewModel.selectedFileURL?.lastPathComponent ?? "Source")
        } detail: {
            DiagramDetailView(viewModel: viewModel)
        }
        .frame(minWidth: 1200)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Open…", systemImage: "folder", action: openPanel)
                    .help("Open Swift files or directories (⌘O)")
                    .accessibilityIdentifier("toolbarOpenButton")
                #if !APP_STORE_BUILD
                Button("Open Package…", systemImage: "shippingbox", action: openPackagePanel)
                    .help("Open an SPM package directory (⇧⌘O)")
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                    .accessibilityIdentifier("toolbarOpenPackageButton")
                #endif

                Text(viewModel.pathSummary)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 300, alignment: .leading)

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
                .accessibilityIdentifier("toolbarSaveButton")
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
        panel.allowedContentTypes = [.swiftSource, .coreDataModelBundle].compactMap { $0 }
        panel.canSelectHiddenExtension = true
        panel.message = "Select Swift sources, directories, or a Core Data .xcdatamodeld bundle"

        guard panel.runModal() == .OK else { return }
        viewModel.unloadPackage()
        let urls = panel.urls
        viewModel.applySelection(
            paths: urls.map { $0.path() },
            bookmarks: urls.map { SecurityScopedURL.makeBookmark(for: $0) },
            urls: urls
        )
        viewModel.generate()
    }

    #if !APP_STORE_BUILD
    private func openPackagePanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose the directory that contains your Package.swift"
        panel.prompt = "Open Package"

        guard panel.runModal() == .OK, let url = panel.urls.first else { return }
        Task {
            await viewModel.loadPackage(at: url)
            if viewModel.packageDescription != nil {
                viewModel.generate()
            }
        }
    }
    #endif
}

extension Notification.Name {
    static let openFile = Notification.Name("openFile")
}

extension UTType {
    /// Core Data model bundle (.xcdatamodeld). Created lazily from the
    /// filename extension because the registered system UTI is
    /// `com.apple.xcode.coredata-momd` and may not be available unless
    /// Xcode is installed; the extension-based form is always recognised.
    static var coreDataModelBundle: UTType? {
        UTType(filenameExtension: "xcdatamodeld")
            ?? UTType("com.apple.xcode.coredata-momd")
    }
}

#Preview {
    ContentView()
        .environment(SubscriptionManager())
}
