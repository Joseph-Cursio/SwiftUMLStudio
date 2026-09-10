import Foundation
import Observation
import SwiftData
import SwiftUMLBridgeFramework

@Observable @MainActor
final class DiagramViewModel {
    var selectedPaths: [String] = []
    /// Security-scoped bookmarks aligned with `selectedPaths`. Populated by
    /// `applySelection(paths:bookmarks:urls:)` when the user picks files via
    /// `NSOpenPanel`, and re-derived from persisted bookmarks when restoring
    /// a saved diagram. Direct assignment to `selectedPaths` (tests, package
    /// load) leaves this empty — those code paths don't depend on cross-session
    /// access being restored.
    var selectedPathBookmarks: [Data?] = []
    /// URLs the view model has explicitly started security-scoped access on
    /// (bookmark-resolved URLs from `applySelection`). Held so `deinit` can
    /// balance the `startAccessingSecurityScopedResource()` calls.
    private var activeSecurityScopedURLs: [URL] = []
    var script: DiagramScript?
    var sequenceScript: SequenceScript?
    var depsScript: DepsScript?
    var stateScript: StateScript?
    var activityScript: ActivityScript?
    var erScript: ERScript?
    var componentScript: ComponentScript?

    // For restoring from history without needing to re-parse AST.
    // Not `private` so the `DiagramViewModel+Workspace` extension can set it.
    var restoredScript: SimpleDiagramScript?

    var isGenerating: Bool = false
    var errorMessage: String?
    /// Non-fatal notice set by `restoreSelection(from:)` when one or more saved
    /// files couldn't be restored (sandbox can't read them without a bookmark,
    /// or the bookmark was unresolvable). Distinct from `errorMessage` because
    /// `generate()` clears `errorMessage` at the start of every run, and
    /// restoring a snapshot triggers a generate via `onChange(selectedPaths)`
    /// — the notice would be wiped before the UI could display it.
    var restoreNotice: String?
    #if APP_STORE_BUILD
    // Default to Mermaid in the sandbox build so new users don't ship their
    // diagram source to planttext.com on first launch. PlantUML stays
    // available behind a one-time consent prompt — see [[PlantUMLConsent]].
    var diagramFormat: DiagramFormat = .mermaid
    #else
    var diagramFormat: DiagramFormat = .plantuml
    #endif
    var diagramMode: DiagramMode = .classDiagram
    var entryPoint: String = ""
    var availableEntryPoints: [String] = []
    var sequenceDepth: Int = 3
    var depsMode: DepsMode = .types
    var stateIdentifier: String = ""
    var availableStateMachines: [StateMachineModel] = []

    /// The full model backing the currently-selected state machine, if any.
    var currentStateMachineModel: StateMachineModel? {
        availableStateMachines.first(where: { $0.identifier == stateIdentifier })
    }

    var fileTree: [FileNode] = []
    var selectedFileURL: URL?
    var selectedFileContent: String = ""

    /// 1-based line to highlight in `SourceEditorView`. Set by
    /// `revealSource(at:)`; cleared whenever the user manually selects a file.
    var highlightedSourceLine: Int?

    /// Set by `loadPackage(at:)` when the user opens an SPM package directory.
    /// Generation dispatches to the package-aware entry point so each type is
    /// stamped with its owning target.
    var packageRoot: URL?
    var packageDescription: SPMPackageDescription?
    /// Surfaced via the failure alert when SPMPackageReader.describe(at:)
    /// throws (swift toolchain missing, malformed manifest, etc.).
    var packageLoadError: String?

    var history: [DiagramEntity] = []
    var selectedHistoryItem: DiagramEntity?

    // Dashboard
    var projectSummary: ProjectSummary?
    var insights: [Insight] = []
    var suggestions: [DiagramSuggestion] = []

    // Architecture Tracking (Phase 4)
    var snapshots: [ProjectSnapshot] = []
    var architectureDiff: ArchitectureDiff?

    var currentTask: Task<Void, Never>?
    let modelContext: ModelContext
    let classGenerator: any ClassDiagramGenerating
    let sequenceGenerator: any SequenceDiagramGenerating
    let depsGenerator: any DependencyGraphGenerating
    let stateGenerator: any StateMachineGenerating
    let activityGenerator: any ActivityDiagramGenerating
    let erGenerator: any ERDiagramGenerating
    let componentGenerator: any ComponentDiagramGenerating

    init(
        // Declined. `PersistenceController` is a one-property struct over a SwiftData
        // `ModelContainer`, and its seam is `init(inMemory:)` — which the tests already use
        // **114 times across 12 files**. `concrete-type-usage` is right that this is a
        // dependency and not a kernel (SwiftProjectLint's own notes name it as one of the two types
        // that forced its kernel storage test to be a positive check rather than a denylist), and
        // the substitution it asks for is already available in the form SwiftData supports.
        // A protocol over `container: ModelContainer` would abstract the one property whose type is
        // the thing a test varies.
        // swiftprojectlint:disable:next concrete-type-usage
        persistenceController: PersistenceController = PersistenceController.shared,
        classGenerator: any ClassDiagramGenerating = ClassDiagramGenerator(),
        sequenceGenerator: any SequenceDiagramGenerating = SequenceDiagramGenerator(),
        depsGenerator: any DependencyGraphGenerating = DependencyGraphGenerator(),
        stateGenerator: any StateMachineGenerating = StateMachineGenerator(),
        activityGenerator: any ActivityDiagramGenerating = ActivityDiagramGenerator(),
        erGenerator: any ERDiagramGenerating = ERDiagramGenerator(),
        componentGenerator: any ComponentDiagramGenerating = ComponentDiagramGenerator()
    ) {
        self.modelContext = persistenceController.container.mainContext
        self.classGenerator = classGenerator
        self.sequenceGenerator = sequenceGenerator
        self.depsGenerator = depsGenerator
        self.stateGenerator = stateGenerator
        self.activityGenerator = activityGenerator
        self.erGenerator = erGenerator
        self.componentGenerator = componentGenerator
    }

    var currentScript: (any DiagramOutputting)? {
        if let restoredScript { return restoredScript }

        switch diagramMode {
        case .classDiagram: return script
        case .sequenceDiagram: return sequenceScript
        case .dependencyGraph: return depsScript
        case .stateMachine: return stateScript
        case .activityDiagram: return activityScript
        case .erDiagram: return erScript
        case .componentDiagram: return componentScript
        }
    }

    var pathSummary: String {
        switch selectedPaths.count {
        case 0:
            return "No source selected"
        case 1:
            return URL(fileURLWithPath: selectedPaths[0]).lastPathComponent
        default:
            let first = URL(fileURLWithPath: selectedPaths[0]).lastPathComponent
            return "\(first) + \(selectedPaths.count - 1) more"
        }
    }

    func generate() {
        currentTask?.cancel()
        isGenerating = true
        errorMessage = nil
        selectedHistoryItem = nil
        restoredScript = nil

        currentTask = Task { [weak self] in
            guard let self else { return }

            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            switch self.diagramMode {
            case .classDiagram:
                await self.generateClassDiagram()
            case .sequenceDiagram:
                await self.generateSequenceDiagram()
            case .dependencyGraph:
                await self.generateDependencyGraph()
            case .stateMachine:
                await self.generateStateMachineDiagram()
            case .activityDiagram:
                await self.generateActivityDiagram()
            case .erDiagram:
                await self.generateERDiagram()
            case .componentDiagram:
                await self.generateComponentDiagram()
            }

            guard !Task.isCancelled else { return }
            self.isGenerating = false
        }
    }

    /// One save is one event, so it reads the clock once and hands the same instant to both
    /// records. They used to take an independent read each, which meant a history entry and the
    /// snapshot beside it disagreed about when the user pressed Save.
    func save(isProUnlocked: Bool = false, at savedAt: Date = Date()) {
        saveToHistory(at: savedAt)
        saveSnapshot(isProUnlocked: isProUnlocked, at: savedAt)
    }

    /// Replace the current selection with a freshly granted set of paths.
    /// Stops security-scoped access on any previously held URLs and starts
    /// access on the new ones. `urls` is the live `URL` array — pass URLs
    /// granted by `NSOpenPanel` (already accessible; the start call is
    /// harmless) or URLs resolved from persisted bookmarks (start is
    /// required for sandbox read access).
    func applySelection(paths: [String], bookmarks: [Data?], urls: [URL]) {
        for url in activeSecurityScopedURLs {
            url.stopAccessingSecurityScopedResource()
        }
        activeSecurityScopedURLs = urls
        for url in urls {
            _ = url.startAccessingSecurityScopedResource()
        }
        selectedPaths = paths
        selectedPathBookmarks = bookmarks
    }
}

/// A simple implementation of DiagramOutputting for restoring history items.
struct SimpleDiagramScript: DiagramOutputting {
    let text: String
    let format: DiagramFormat

    func encodeText() -> String {
        text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
    }
}
