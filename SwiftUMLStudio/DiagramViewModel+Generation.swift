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
        let packageDescription = self.packageDescription
        let packageRoot = self.packageRoot

        let generator = classGenerator
        let result = await Task.detached(priority: .userInitiated) {
            var config = Configuration.default
            config.format = format
            if let packageDescription, let packageRoot {
                return generator.generateScript(
                    forPackage: packageDescription,
                    packageRoot: packageRoot,
                    with: config,
                    sdkPath: nil
                )
            }
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
        let packageDescription = self.packageDescription
        let packageRoot = self.packageRoot

        let generator = depsGenerator
        let result = await Task.detached(priority: .userInitiated) {
            var config = Configuration.default
            config.format = format
            if let packageDescription, let packageRoot {
                return generator.generateScript(
                    forPackage: packageDescription,
                    packageRoot: packageRoot,
                    mode: mode,
                    with: config,
                    sdkPath: nil
                )
            }
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

    /// Resolve `entryPoint` into a `Type.method` pair. On missing paths/entry or
    /// a malformed value, clears `isGenerating` and returns nil so the caller can
    /// abort the generation.
    private func resolveEntryPoint() -> (entryType: String, entryMethod: String)? {
        guard !selectedPaths.isEmpty, !entryPoint.isEmpty else {
            isGenerating = false
            return nil
        }
        let parts = entryPoint.split(separator: ".").map(String.init)
        guard parts.count == 2 else {
            isGenerating = false
            return nil
        }
        return (parts[0], parts[1])
    }

    func generateActivityDiagram() async {
        guard let (entryType, entryMethod) = resolveEntryPoint() else { return }

        activityScript = nil

        let paths = selectedPaths
        let format = diagramFormat

        let generator = activityGenerator
        let result = await Task.detached(priority: .userInitiated) {
            var config = Configuration.default
            config.format = format
            return generator.generateScript(
                for: paths, entryType: entryType,
                entryMethod: entryMethod, with: config
            )
        }.value

        guard !Task.isCancelled else { return }
        activityScript = result
    }

    func generateComponentDiagram() async {
        guard let description = packageDescription, let root = packageRoot else {
            componentScript = nil
            #if APP_STORE_BUILD
            errorMessage = "Component diagrams require an open Swift Package. "
                + "Package loading isn't available in the App Store build — "
                + "use the direct-download version for SPM support."
            #else
            errorMessage = "Component diagrams require an open Swift Package. "
                + "Use Open Package… to load a Package.swift directory."
            #endif
            isGenerating = false
            return
        }
        componentScript = nil

        let format = diagramFormat
        let generator = componentGenerator
        let result = await Task.detached(priority: .userInitiated) {
            var config = Configuration.default
            config.format = format
            return generator.generateScript(
                forPackage: description, packageRoot: root, with: config
            )
        }.value

        guard !Task.isCancelled else { return }
        componentScript = result
    }

    func generateERDiagram() async {
        guard !selectedPaths.isEmpty else {
            isGenerating = false
            return
        }
        erScript = nil

        let paths = selectedPaths
        let format = diagramFormat

        let generator = erGenerator
        let result = await Task.detached(priority: .userInitiated) {
            var config = Configuration.default
            config.format = format
            return generator.generateScript(for: paths, with: config)
        }.value

        guard !Task.isCancelled else { return }
        erScript = result
    }

    func generateSequenceDiagram() async {
        guard let (entryType, entryMethod) = resolveEntryPoint() else { return }

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
        } else if diagramMode == .activityDiagram {
            entity.entryPoint = entryPoint
        }

        entity.sequenceDepth = sequenceDepth
        entity.scriptText = currentScript.text
        entity.paths = try? JSONEncoder().encode(selectedPaths)
        entity.pathBookmarks = selectedPathBookmarks.isEmpty
            ? nil
            : try? JSONEncoder().encode(selectedPathBookmarks)

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
