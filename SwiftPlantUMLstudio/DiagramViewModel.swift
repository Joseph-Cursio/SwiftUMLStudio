//
//  DiagramViewModel.swift
//  SwiftPlantUMLstudio
//
//  Created by joe cursio on 2/27/26.
//

import Observation
import SwiftUMLBridgeFramework

enum DiagramMode: String, CaseIterable, Identifiable {
    case classDiagram = "Class Diagram"
    case sequenceDiagram = "Sequence Diagram"
    case dependencyGraph = "Dependency Graph"
    var id: String { rawValue }
}

@Observable @MainActor
final class DiagramViewModel {
    var selectedPaths: [String] = []
    var script: DiagramScript?
    var sequenceScript: SequenceScript?
    var depsScript: DepsScript?
    var isGenerating: Bool = false
    var errorMessage: String?
    var diagramFormat: DiagramFormat = .plantuml
    var diagramMode: DiagramMode = .classDiagram
    var entryPoint: String = ""
    var sequenceDepth: Int = 3
    var depsMode: DepsMode = .types

    private var currentTask: Task<Void, Never>?

    var currentScript: (any DiagramOutputting)? {
        switch diagramMode {
        case .classDiagram: return script
        case .sequenceDiagram: return sequenceScript
        case .dependencyGraph: return depsScript
        }
    }

    func generate() {
        currentTask?.cancel()
        currentTask = Task {
            switch diagramMode {
            case .classDiagram:
                await generateClassDiagram()
            case .sequenceDiagram:
                await generateSequenceDiagram()
            case .dependencyGraph:
                await generateDependencyGraph()
            }
        }
    }

    private func generateClassDiagram() async {
        guard !selectedPaths.isEmpty else { return }
        isGenerating = true
        errorMessage = nil
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
        isGenerating = false
    }

    private func generateDependencyGraph() async {
        guard !selectedPaths.isEmpty else { return }
        isGenerating = true
        errorMessage = nil
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
        isGenerating = false
    }

    private func generateSequenceDiagram() async {
        guard !selectedPaths.isEmpty, !entryPoint.isEmpty else { return }
        let parts = entryPoint.split(separator: ".").map(String.init)
        guard parts.count == 2 else { return }
        let entryType = parts[0]
        let entryMethod = parts[1]

        isGenerating = true
        errorMessage = nil
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
        isGenerating = false
    }
}
