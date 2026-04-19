import Foundation
import SwiftData
import SwiftUMLBridgeFramework

// MARK: - Diagram Generation

extension DiagramViewModel {

    func generateClassDiagram() async {
        guard !selectedPaths.isEmpty else {
            isGenerating = false
            return
        }
        script = nil

        let paths = selectedPaths
        let format = diagramFormat

        let generator = classGenerator
        let result = await Task.detached(priority: .userInitiated) {
            var config = Configuration.default
            config.format = format
            return generator.generateScript(for: paths, with: config)
        }.value

        guard !Task.isCancelled else { return }
        script = result
    }

    func generateDependencyGraph() async {
        guard !selectedPaths.isEmpty else {
            isGenerating = false
            return
        }
        depsScript = nil

        let paths = selectedPaths
        let format = diagramFormat
        let mode = depsMode

        let generator = depsGenerator
        let result = await Task.detached(priority: .userInitiated) {
            var config = Configuration.default
            config.format = format
            return generator.generateScript(for: paths, mode: mode, with: config)
        }.value

        guard !Task.isCancelled else { return }
        depsScript = result
    }

    func generateStateMachineDiagram() async {
        guard !selectedPaths.isEmpty, !stateIdentifier.isEmpty else {
            isGenerating = false
            return
        }

        stateScript = nil

        let paths = selectedPaths
        let format = diagramFormat
        let identifier = stateIdentifier

        let generator = stateGenerator
        let result = await Task.detached(priority: .userInitiated) {
            var config = Configuration.default
            config.format = format
            return generator.generateScript(
                for: paths, stateIdentifier: identifier, with: config
            )
        }.value

        guard !Task.isCancelled else { return }
        stateScript = result
    }

    func generateSequenceDiagram() async {
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

        let generator = sequenceGenerator
        let result = await Task.detached(priority: .userInitiated) {
            var config = Configuration.default
            config.format = format
            return generator.generateScript(
                for: paths, entryType: entryType,
                entryMethod: entryMethod, depth: depth, with: config
            )
        }.value

        guard !Task.isCancelled else { return }
        sequenceScript = result
    }

    func saveToHistory() {
        guard let currentScript = currentScript else { return }

        let entity = DiagramEntity()
        entity.identifier = UUID()
        entity.timestamp = Date()
        entity.mode = diagramMode.rawValue
        entity.format = diagramFormat.rawValue

        if diagramMode == .sequenceDiagram {
            entity.entryPoint = entryPoint
        } else if diagramMode == .dependencyGraph {
            entity.entryPoint = depsMode.rawValue
        } else if diagramMode == .stateMachine {
            entity.entryPoint = stateIdentifier
        }

        entity.sequenceDepth = sequenceDepth
        entity.scriptText = currentScript.text
        entity.paths = try? JSONEncoder().encode(selectedPaths)

        if let firstPath = selectedPaths.first {
            let filename = URL(fileURLWithPath: firstPath).lastPathComponent
            entity.name = selectedPaths.count > 1
                ? "\(filename) + \(selectedPaths.count - 1)"
                : filename
        } else {
            entity.name = "Untitled Diagram"
        }

        modelContext.insert(entity)
        try? modelContext.save()
        loadHistory()
    }
}
