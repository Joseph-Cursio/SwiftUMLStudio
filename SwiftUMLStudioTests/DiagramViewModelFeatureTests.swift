//
//  DiagramViewModelFeatureTests.swift
//  SwiftUMLStudioTests
//
//  Unit tests for DiagramViewModel features: save name generation, selectFile,
//  architectureDiff, analyzeProject, and saveSnapshot.
//

import Foundation
import SwiftData
import Testing
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio

// MARK: - GCD dispatch helpers

private func runOnMain(_ block: @MainActor () -> Void) {
    if Thread.isMainThread {
        MainActor.assumeIsolated(block)
    } else {
        DispatchQueue.main.sync { MainActor.assumeIsolated(block) }
    }
}

// MARK: - DiagramViewModel Feature Tests

@Suite("DiagramViewModel Features")
struct DiagramViewModelFeatureTests {

    // MARK: - analyzeProject

    @Test("analyzeProject with empty paths clears summary and insights")
    func analyzeProjectEmptyPaths() {
        runOnMain {
            let persistence = PersistenceController(inMemory: true)
            let viewModel = DiagramViewModel(persistenceController: persistence)
            viewModel.selectedPaths = []

            viewModel.analyzeProject()

            #expect(viewModel.projectSummary == nil)
            #expect(viewModel.insights.isEmpty)
            #expect(viewModel.suggestions.isEmpty)
        }
    }

    // MARK: - saveToHistory name generation

    @Test("save with multiple paths generates name with count")
    func saveMultiplePathsName() {
        runOnMain {
            let persistence = PersistenceController(inMemory: true)
            let modelContext = persistence.container.mainContext
            let viewModel = DiagramViewModel(persistenceController: persistence)
            viewModel.selectedPaths = ["/a/First.swift", "/b/Second.swift"]
            viewModel.diagramMode = .classDiagram
            viewModel.diagramFormat = .plantuml

            let entity = DiagramEntity()
            entity.scriptText = "@startuml\n@enduml"
            modelContext.insert(entity)
            viewModel.loadDiagram(entity)

            viewModel.save()
            viewModel.loadHistory()

            let saved = viewModel.history.first
            #expect(saved?.name == "First.swift + 1")
        }
    }

    @Test("save with no paths generates Untitled Diagram name")
    func saveNoPathsName() {
        runOnMain {
            let persistence = PersistenceController(inMemory: true)
            let modelContext = persistence.container.mainContext
            let viewModel = DiagramViewModel(persistenceController: persistence)
            viewModel.selectedPaths = []
            viewModel.diagramMode = .classDiagram

            let entity = DiagramEntity()
            entity.scriptText = "@startuml\n@enduml"
            modelContext.insert(entity)
            viewModel.loadDiagram(entity)

            viewModel.save()
            viewModel.loadHistory()

            let saved = viewModel.history.first
            #expect(saved?.name == "Untitled Diagram")
        }
    }

    @Test("save for sequence diagram stores entryPoint")
    func saveSequenceDiagramStoresEntryPoint() {
        runOnMain {
            let persistence = PersistenceController(inMemory: true)
            let modelContext = persistence.container.mainContext
            let viewModel = DiagramViewModel(persistenceController: persistence)
            viewModel.selectedPaths = ["/tmp/Foo.swift"]
            viewModel.diagramMode = .sequenceDiagram
            viewModel.entryPoint = "Foo.bar"
            viewModel.diagramFormat = .plantuml

            let entity = DiagramEntity()
            entity.mode = DiagramMode.sequenceDiagram.rawValue
            entity.scriptText = "sequenceDiagram\nFoo->>Bar: bar()"
            modelContext.insert(entity)
            viewModel.loadDiagram(entity)

            viewModel.save()
            viewModel.loadHistory()

            let saved = viewModel.history.first
            #expect(saved?.entryPoint == "Foo.bar")
        }
    }

    @Test("save for dependency graph stores depsMode in entryPoint field")
    func saveDependencyGraphStoresDepsMode() {
        runOnMain {
            let persistence = PersistenceController(inMemory: true)
            let modelContext = persistence.container.mainContext
            let viewModel = DiagramViewModel(persistenceController: persistence)
            viewModel.selectedPaths = ["/tmp/Foo.swift"]
            viewModel.diagramMode = .dependencyGraph
            viewModel.depsMode = .modules
            viewModel.diagramFormat = .plantuml

            let entity = DiagramEntity()
            entity.mode = DiagramMode.dependencyGraph.rawValue
            entity.entryPoint = DepsMode.modules.rawValue
            entity.scriptText = "@startuml\ndeps\n@enduml"
            modelContext.insert(entity)
            viewModel.loadDiagram(entity)

            viewModel.save()
            viewModel.loadHistory()

            let saved = viewModel.history.first
            #expect(saved?.entryPoint == DepsMode.modules.rawValue)
        }
    }

    // MARK: - selectFile edge cases

    @Test("selectFile with unreadable URL shows fallback message")
    func selectFileUnreadable() {
        runOnMain {
            let viewModel = DiagramViewModel(
                persistenceController: PersistenceController(inMemory: true)
            )
            let bogusURL = URL(fileURLWithPath: "/nonexistent/path/Fake.swift")
            viewModel.selectFile(bogusURL)
            #expect(viewModel.selectedFileContent == "// Could not read file")
            #expect(viewModel.selectedFileURL == bogusURL)
        }
    }

    // MARK: - updateArchitectureDiff

    @Test("updateArchitectureDiff sets nil when no summary")
    func updateArchitectureDiffNoSummary() {
        runOnMain {
            let viewModel = DiagramViewModel(
                persistenceController: PersistenceController(inMemory: true)
            )
            viewModel.selectedPaths = ["/tmp/something"]
            viewModel.projectSummary = nil

            viewModel.updateArchitectureDiff()

            #expect(viewModel.architectureDiff == nil)
        }
    }

    @Test("updateArchitectureDiff sets nil when paths empty")
    func updateArchitectureDiffEmptyPaths() {
        runOnMain {
            let viewModel = DiagramViewModel(
                persistenceController: PersistenceController(inMemory: true)
            )
            viewModel.selectedPaths = []

            viewModel.updateArchitectureDiff()

            #expect(viewModel.architectureDiff == nil)
        }
    }

    // MARK: - saveSnapshot

    @Test("saveSnapshot does nothing when not pro unlocked")
    func saveSnapshotNotPro() {
        runOnMain {
            let persistence = PersistenceController(inMemory: true)
            let viewModel = DiagramViewModel(persistenceController: persistence)
            viewModel.selectedPaths = ["/tmp/Foo.swift"]

            viewModel.saveSnapshot(isProUnlocked: false)

            viewModel.loadSnapshots()
            #expect(viewModel.snapshots.isEmpty)
        }
    }

    @Test("saveSnapshot does nothing when summary is nil")
    func saveSnapshotNoSummary() {
        runOnMain {
            let persistence = PersistenceController(inMemory: true)
            let viewModel = DiagramViewModel(persistenceController: persistence)
            viewModel.selectedPaths = ["/tmp/Foo.swift"]
            viewModel.projectSummary = nil

            viewModel.saveSnapshot(isProUnlocked: true)

            viewModel.loadSnapshots()
            #expect(viewModel.snapshots.isEmpty)
        }
    }
}
