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
    var diagramFormat: DiagramFormat = .plantuml
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

    func save(isProUnlocked: Bool = false) {
        saveToHistory()
        saveSnapshot(isProUnlocked: isProUnlocked)
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
