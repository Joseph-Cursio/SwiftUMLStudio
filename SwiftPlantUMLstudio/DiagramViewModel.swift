//
//  DiagramViewModel.swift
//  SwiftPlantUMLstudio
//
//  Created by joe cursio on 2/27/26.
//

import CoreData
import Foundation
import Observation
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
    
    var history: [DiagramEntity] = []
    var selectedHistoryItem: DiagramEntity?

    private var currentTask: Task<Void, Never>?
    private let context: NSManagedObjectContext

    init(persistenceController: PersistenceController = PersistenceController.shared) {
        self.context = persistenceController.container.viewContext
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
            
            // Debounce: wait for a short period before starting expensive AST parsing
            // to handle rapid-fire setting changes smoothly.
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
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

    func save() {
        saveToHistory()
    }

    func loadHistory() {
        let request = NSFetchRequest<DiagramEntity>(entityName: "DiagramEntity")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \DiagramEntity.timestamp, ascending: false)]
        do {
            history = try context.fetch(request)
        } catch {
            print("Failed to fetch history: \(error)")
        }
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
        
        sequenceDepth = Int(entity.sequenceDepth)
        
        if let pathsData = entity.paths,
           let paths = try? JSONDecoder().decode([String].self, from: pathsData) {
            selectedPaths = paths
        }

        // Restore the script text so the diagram appears immediately
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
        context.delete(entity)
        try? context.save()
        loadHistory()
    }

    func refreshEntryPoints() {
        guard !selectedPaths.isEmpty else {
            availableEntryPoints = []
            return
        }
        
        // This is fast enough to do on the main actor since it's just syntax scanning
        // without full type checking or SourceKit XPC.
        availableEntryPoints = SequenceDiagramGenerator().findEntryPoints(for: selectedPaths)
    }

    private func saveToHistory() {
        guard let currentScript = currentScript else { return }
        
        let entity = DiagramEntity(context: context)
        entity.id = UUID()
        entity.timestamp = Date()
        entity.mode = diagramMode.rawValue
        entity.format = diagramFormat.rawValue
        
        if diagramMode == .sequenceDiagram {
            entity.entryPoint = entryPoint
        } else if diagramMode == .dependencyGraph {
            entity.entryPoint = depsMode.rawValue
        }
        
        entity.sequenceDepth = Int16(sequenceDepth)
        entity.scriptText = currentScript.text
        entity.paths = try? JSONEncoder().encode(selectedPaths)
        
        // Generate a descriptive name
        if let firstPath = selectedPaths.first {
            let filename = URL(fileURLWithPath: firstPath).lastPathComponent
            if selectedPaths.count > 1 {
                entity.name = "\(filename) + \(selectedPaths.count - 1)"
            } else {
                entity.name = filename
            }
        } else {
            entity.name = "Untitled Diagram"
        }
        
        try? context.save()
        loadHistory()
    }

    private func generateClassDiagram() async {
        guard !selectedPaths.isEmpty else { 
            isGenerating = false
            return 
        }
        script = nil

        let paths = selectedPaths
        let format = diagramFormat
        
        let result = await Task.detached(priority: .userInitiated) {
            var config = Configuration.default
            config.format = format
            return ClassDiagramGenerator().generateScript(for: paths, with: config)
        }.value
        
        guard !Task.isCancelled else { return }
        script = result
    }

    private func generateDependencyGraph() async {
        guard !selectedPaths.isEmpty else {
            isGenerating = false
            return
        }
        depsScript = nil

        let paths = selectedPaths
        let format = diagramFormat
        let mode = depsMode
        
        let result = await Task.detached(priority: .userInitiated) {
            var config = Configuration.default
            config.format = format
            return DependencyGraphGenerator().generateScript(for: paths, mode: mode, with: config)
        }.value
        
        guard !Task.isCancelled else { return }
        depsScript = result
    }

    private func generateSequenceDiagram() async {
        guard !selectedPaths.isEmpty, !entryPoint.isEmpty else {
            isGenerating = false
            return
        }
        let parts = entryPoint.split(separator: ".").map(String.init)
        guard parts.count == 2 else {
            isGenerating = false
            return
        }
        let entryType = parts[0]
        let entryMethod = parts[1]

        sequenceScript = nil

        let paths = selectedPaths
        let format = diagramFormat
        let depth = sequenceDepth
        
        let result = await Task.detached(priority: .userInitiated) {
            var config = Configuration.default
            config.format = format
            return SequenceDiagramGenerator().generateScript(
                for: paths,
                entryType: entryType,
                entryMethod: entryMethod,
                depth: depth,
                with: config
            )
        }.value
        
        guard !Task.isCancelled else { return }
        sequenceScript = result
    }
}

/// A simple implementation of DiagramOutputting for restoring history items.
private struct SimpleDiagramScript: DiagramOutputting {
    let text: String
    let format: DiagramFormat

    func encodeText() -> String {
        // Use a simple percent encoding as a fallback for history restoration.
        // In a real app, we'd expose the framework's encoding more formally.
        text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
    }
}
