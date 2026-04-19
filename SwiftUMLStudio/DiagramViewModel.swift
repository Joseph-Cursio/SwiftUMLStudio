import Foundation
import Observation
import SwiftData
import SwiftUMLBridgeFramework

@Observable @MainActor
final class DiagramViewModel {
    var selectedPaths: [String] = []
    var script: DiagramScript?
    var sequenceScript: SequenceScript?
    var depsScript: DepsScript?

    // For restoring from history without needing to re-parse AST
    private var restoredScript: SimpleDiagramScript?

    var isGenerating: Bool = false
    var errorMessage: String?
    var diagramFormat: DiagramFormat = .plantuml
    var diagramMode: DiagramMode = .classDiagram
    var entryPoint: String = ""
    var availableEntryPoints: [String] = []
    var sequenceDepth: Int = 3
    var depsMode: DepsMode = .types

    var fileTree: [FileNode] = []
    var selectedFileURL: URL?
    var selectedFileContent: String = ""

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

    init(
        persistenceController: PersistenceController = PersistenceController.shared,
        classGenerator: any ClassDiagramGenerating = ClassDiagramGenerator(),
        sequenceGenerator: any SequenceDiagramGenerating = SequenceDiagramGenerator(),
        depsGenerator: any DependencyGraphGenerating = DependencyGraphGenerator()
    ) {
        self.modelContext = persistenceController.container.mainContext
        self.classGenerator = classGenerator
        self.sequenceGenerator = sequenceGenerator
        self.depsGenerator = depsGenerator
    }

    var currentScript: (any DiagramOutputting)? {
        if let restoredScript { return restoredScript }

        switch diagramMode {
        case .classDiagram: return script
        case .sequenceDiagram: return sequenceScript
        case .dependencyGraph: return depsScript
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
            }

            guard !Task.isCancelled else { return }
            self.isGenerating = false
        }
    }

    func save(isProUnlocked: Bool = false) {
        saveToHistory()
        saveSnapshot(isProUnlocked: isProUnlocked)
    }

    func loadHistory() {
        let descriptor = FetchDescriptor<DiagramEntity>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        history = (try? modelContext.fetch(descriptor)) ?? []
    }

    func loadDiagram(_ entity: DiagramEntity) {
        let modeString = entity.mode ?? ""
        let formatString = entity.format ?? ""

        diagramMode = DiagramMode(rawValue: modeString) ?? .classDiagram
        diagramFormat = DiagramFormat(rawValue: formatString) ?? .plantuml

        if diagramMode == .sequenceDiagram {
            entryPoint = entity.entryPoint ?? ""
            refreshEntryPoints()
        } else if diagramMode == .dependencyGraph {
            depsMode = DepsMode(rawValue: entity.entryPoint ?? "") ?? .types
        }

        sequenceDepth = entity.sequenceDepth

        if let pathsData = entity.paths,
           let paths = try? JSONDecoder().decode([String].self, from: pathsData) {
            selectedPaths = paths
        }

        if let text = entity.scriptText {
            restoredScript = SimpleDiagramScript(text: text, format: diagramFormat)
        } else {
            restoredScript = nil
        }
    }

    func deleteHistoryItem(_ entity: DiagramEntity) {
        if selectedHistoryItem == entity {
            selectedHistoryItem = nil
            restoredScript = nil
        }
        modelContext.delete(entity)
        try? modelContext.save()
        loadHistory()
    }

    func rebuildFileTree() {
        fileTree = FileNode.buildTree(from: selectedPaths)
        if let url = selectedFileURL {
            let allURLs = FileNode.allLeafURLs(from: fileTree)
            if !allURLs.contains(url) {
                selectedFileURL = nil
                selectedFileContent = ""
            }
        }
        if selectedFileURL == nil {
            if let firstURL = FileNode.allLeafURLs(from: fileTree).first {
                selectFile(firstURL)
            }
        }
    }

    func loadSnapshots() {
        snapshots = SnapshotManager.fetchSnapshots(modelContext: modelContext)
    }

    func saveSnapshot(isProUnlocked: Bool) {
        guard isProUnlocked, let summary = projectSummary else { return }
        SnapshotManager.saveSnapshot(from: summary, paths: selectedPaths, modelContext: modelContext)
        loadSnapshots()
        updateArchitectureDiff()
        ReviewReminderManager.rescheduleIfEnabled()
    }

    func deleteSnapshot(_ snapshot: ProjectSnapshot) {
        SnapshotManager.deleteSnapshot(snapshot, modelContext: modelContext)
        loadSnapshots()
        updateArchitectureDiff()
    }

    func updateArchitectureDiff() {
        guard let summary = projectSummary, !selectedPaths.isEmpty else {
            architectureDiff = nil
            return
        }
        if let previous = SnapshotManager.latestSnapshot(
            for: selectedPaths, modelContext: modelContext
        ) {
            architectureDiff = SnapshotManager.computeDiff(current: summary, previous: previous)
        } else {
            architectureDiff = nil
        }
    }

    func analyzeProject(isProUnlocked: Bool = true) {
        guard !selectedPaths.isEmpty else {
            projectSummary = nil
            insights = []
            suggestions = []
            return
        }
        let paths = selectedPaths
        let proUnlocked = isProUnlocked
        Task {
            let (summary, newInsights, newSuggestions) = await Task.detached(
                priority: .userInitiated
            ) {
                let result = ProjectAnalyzer.analyze(paths: paths)
                let insights = InsightEngine.generate(from: result)
                let suggestions = SuggestionEngine.generate(
                    from: result, isProUnlocked: proUnlocked
                )
                return (result, insights, suggestions)
            }.value
            projectSummary = summary
            insights = newInsights
            suggestions = newSuggestions
            updateArchitectureDiff()
        }
    }

    func selectFile(_ url: URL?) {
        selectedFileURL = url
        guard let url else {
            selectedFileContent = ""
            return
        }
        selectedFileContent = (try? String(contentsOf: url, encoding: .utf8))
            ?? "// Could not read file"
    }

    func refreshEntryPoints() {
        guard !selectedPaths.isEmpty else {
            availableEntryPoints = []
            return
        }
        availableEntryPoints = sequenceGenerator.findEntryPoints(for: selectedPaths)
    }

}

/// A simple implementation of DiagramOutputting for restoring history items.
private struct SimpleDiagramScript: DiagramOutputting {
    let text: String
    let format: DiagramFormat

    func encodeText() -> String {
        text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
    }
}
