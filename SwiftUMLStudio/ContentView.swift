import SwiftUI
import SwiftUMLBridgeFramework
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @State private var viewModel = DiagramViewModel()
    @State private var showPaywall = false
    /// Holds the format the user just selected that requires consent (always
    /// `.plantuml` today) plus the previous format to revert to on cancel.
    @State private var plantUMLConsentRequest: (previous: DiagramFormat, requested: DiagramFormat)?
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
        .onChange(of: viewModel.diagramFormat) { oldValue, newValue in
            // PlantUML rendering goes through planttext.com (third-party HTTPS
            // upload of the diagram source). Gate the first selection behind
            // explicit consent; subsequent selections proceed normally.
            if newValue == .plantuml && !PlantUMLConsent.hasConsented {
                plantUMLConsentRequest = (previous: oldValue, requested: newValue)
                return
            }
            viewModel.generate()
        }
        .onChange(of: viewModel.entryPoint) { viewModel.generate() }
        .onChange(of: viewModel.sequenceDepth) { viewModel.generate() }
        .onChange(of: viewModel.depsMode) { viewModel.generate() }
        .onChange(of: viewModel.stateIdentifier) { viewModel.generate() }
        .sheet(isPresented: $showPaywall) {
            PaywallView(subscriptionManager: subscriptionManager)
        }
        .modifier(NoticeAlerts(viewModel: viewModel))
        .modifier(PlantUMLConsentAlert(
            viewModel: viewModel,
            request: $plantUMLConsentRequest
        ))
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

                PathSummaryLabel(pathSummary: viewModel.pathSummary)

                AppModePicker(appMode: $appMode)

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

/// View-modifier wrapper for the three string-backed notice alerts (generation
/// errors, package-load errors, snapshot restore notices). Extracted from
/// `ContentView.body` so the modifier chain stays inside the SwiftUI
/// type-checker's budget.
private struct NoticeAlerts: ViewModifier {
    @Bindable var viewModel: DiagramViewModel

    func body(content: Content) -> some View {
        content
            .alert(
                "Couldn't generate diagram",
                isPresented: binding(\.errorMessage)
            ) {
                Button("OK", role: .cancel) { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .alert(
                "Couldn't open Swift Package",
                isPresented: binding(\.packageLoadError)
            ) {
                Button("OK", role: .cancel) { viewModel.packageLoadError = nil }
            } message: {
                Text(viewModel.packageLoadError ?? "")
            }
            .alert(
                "Snapshot partially restored",
                isPresented: binding(\.restoreNotice)
            ) {
                Button("OK", role: .cancel) { viewModel.restoreNotice = nil }
            } message: {
                Text(viewModel.restoreNotice ?? "")
            }
    }

    private func binding(
        _ keyPath: ReferenceWritableKeyPath<DiagramViewModel, String?>
    ) -> Binding<Bool> {
        Binding(
            get: { viewModel[keyPath: keyPath] != nil },
            set: { if !$0 { viewModel[keyPath: keyPath] = nil } }
        )
    }
}

/// Consent prompt shown the first time the user selects `.plantuml`. Continue
/// grants persistent consent and proceeds with generation; Cancel reverts the
/// format to whatever was active before the selection.
private struct PlantUMLConsentAlert: ViewModifier {
    let viewModel: DiagramViewModel
    @Binding var request: (previous: DiagramFormat, requested: DiagramFormat)?

    func body(content: Content) -> some View {
        content.alert(
            "Use PlantUML rendering?",
            isPresented: Binding(
                get: { request != nil },
                set: { if !$0 { request = nil } }
            )
        ) {
            Button("Continue") {
                PlantUMLConsent.grant()
                viewModel.generate()
                request = nil
            }
            Button("Cancel", role: .cancel) {
                if let pending = request {
                    viewModel.diagramFormat = pending.previous
                }
                request = nil
            }
        } message: {
            Text(
                "PlantUML diagrams are rendered by planttext.com, a third-party "
                + "service. Your diagram source will be sent over HTTPS to that "
                + "service. Mermaid and Nomnoml render locally without any "
                + "network use."
            )
        }
    }
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
