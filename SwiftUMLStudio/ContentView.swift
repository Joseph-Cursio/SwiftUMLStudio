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

    /// Rebuilds everything derived from the file selection.
    private func handleSelectedPathsChange() {
        viewModel.rebuildFileTree()
        viewModel.generate()
        viewModel.analyzeProject(isProUnlocked: subscriptionManager.isProUnlocked)
        refreshModeDerivedData()
    }

    /// Enforces the paywall for the newly selected diagram mode, then regenerates.
    ///
    /// This was six near-identical `if` blocks inline in `onChange` — one per paid mode, each
    /// repeating the same fallback to `.classDiagram` and the same `showPaywall = true`. Nothing
    /// could reach it: paywall enforcement is business logic that lived only inside a closure a
    /// test cannot call.
    ///
    /// The mode-to-entitlement pairing moved to ``DiagramMode/requiredFeature``, where it is total
    /// by construction and checkable on its own. What is left here is the effect.
    private func handleDiagramModeChange() {
        if let required = viewModel.diagramMode.requiredFeature,
           !FeatureGate.isUnlocked(required, manager: subscriptionManager) {
            viewModel.diagramMode = .classDiagram
            showPaywall = true
            return
        }

        viewModel.generate()
        refreshModeDerivedData()
    }

    /// Refreshes whatever the current mode derives from the selection.
    ///
    /// This decision existed twice — here and in the `selectedPaths` observer — and the two copies
    /// disagreed. This one guarded each call with `!selectedPaths.isEmpty`; the other did not.
    ///
    /// That guard reads like an optimisation and is not one. `refreshEntryPoints()` and
    /// `refreshStateMachines()` both open with `guard !selectedPaths.isEmpty else { … = []; return }`
    /// — emptying the list is *what they do* when there is no selection. Skipping the call
    /// therefore skipped the clearing, so switching to Sequence Diagram with nothing selected left
    /// the entry-point picker showing candidates from files that were no longer selected, while
    /// clearing the selection emptied it correctly.
    ///
    /// One copy, no caller-side guard: both paths now clear.
    private func refreshModeDerivedData() {
        switch viewModel.diagramMode {
        case .sequenceDiagram, .activityDiagram:
            viewModel.refreshEntryPoints()
        case .stateMachine:
            viewModel.refreshStateMachines()
        default:
            break
        }
    }

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
        .onChange(of: viewModel.selectedPaths) { handleSelectedPathsChange() }
        .onChange(of: viewModel.selectedFileURL) {
            viewModel.selectFile(viewModel.selectedFileURL)
        }
        .onChange(of: viewModel.diagramMode) { handleDiagramModeChange() }
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
            Button("Continue") { grantConsent() }
            Button("Cancel", role: .cancel) { declineConsent() }
        } message: {
            Text(
                "PlantUML diagrams are rendered by planttext.com, a third-party "
                + "service. Your diagram source will be sent over HTTPS to that "
                + "service. Mermaid and Nomnoml render locally without any "
                + "network use."
            )
        }
    }

    /// Persist the consent, generate with the format that prompted for it, and dismiss.
    private func grantConsent() {
        PlantUMLConsent.grant()
        viewModel.generate()
        request = nil
    }

    /// Put the format back the way it was before the selection that raised this prompt.
    ///
    /// The restore is the part worth naming: dismissing without it leaves the picker showing
    /// `.plantuml` while nothing was generated, so the UI claims a format the user declined.
    /// `request.previous` exists for exactly this and nothing else reads it.
    private func declineConsent() {
        if let pending = request {
            viewModel.diagramFormat = pending.previous
        }
        request = nil
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
