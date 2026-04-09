//
//  DiagramViewModelHistoryTests.swift
//  SwiftPlantUMLstudioTests
//
//  Unit tests for DiagramViewModel history operations: save, load, delete, and edge cases.
//

import Foundation
import SwiftData
import Testing
import SwiftUMLBridgeFramework
@testable import SwiftPlantUMLstudio

// MARK: - GCD dispatch helpers

private func runOnMain(_ block: @MainActor () -> Void) {
    if Thread.isMainThread {
        MainActor.assumeIsolated(block)
    } else {
        DispatchQueue.main.sync { MainActor.assumeIsolated(block) }
    }
}

// MARK: - DiagramViewModel History Tests

@Suite("DiagramViewModel History")
struct DiagramViewModelHistoryTests {

    // MARK: - save / history

    @Test("save creates a history entity")
    func saveCreatesHistoryEntity() {
        runOnMain {
            let persistence = PersistenceController(inMemory: true)
            let modelContext = persistence.container.mainContext
            let viewModel = DiagramViewModel(persistenceController: persistence)
            viewModel.selectedPaths = ["/tmp/Foo.swift"]
            viewModel.diagramMode = .classDiagram
            viewModel.diagramFormat = .plantuml

            let entity = DiagramEntity()
            entity.identifier = UUID()
            entity.timestamp = Date()
            entity.mode = DiagramMode.classDiagram.rawValue
            entity.format = DiagramFormat.plantuml.rawValue
            entity.scriptText = "@startuml\nclass Foo\n@enduml"
            entity.paths = try? JSONEncoder().encode(["/tmp/Foo.swift"])
            entity.name = "Foo.swift"
            modelContext.insert(entity)
            try? modelContext.save()

            viewModel.loadHistory()
            viewModel.loadDiagram(entity)
            #expect(viewModel.currentScript != nil)

            let countBefore = viewModel.history.count
            viewModel.save()
            #expect(viewModel.history.count == countBefore + 1)
        }
    }

    @Test("loadDiagram restores all properties from entity")
    func loadDiagramRestoresProperties() {
        runOnMain {
            let persistence = PersistenceController(inMemory: true)
            let modelContext = persistence.container.mainContext
            let viewModel = DiagramViewModel(persistenceController: persistence)

            let entity = DiagramEntity()
            entity.identifier = UUID()
            entity.timestamp = Date()
            entity.mode = DiagramMode.sequenceDiagram.rawValue
            entity.format = DiagramFormat.mermaid.rawValue
            entity.entryPoint = "Foo.bar"
            entity.sequenceDepth = 5
            entity.scriptText = "sequenceDiagram\nFoo->>Bar: bar()"
            entity.paths = try? JSONEncoder().encode(["/tmp/Foo.swift"])
            modelContext.insert(entity)

            viewModel.loadDiagram(entity)

            #expect(viewModel.diagramMode == .sequenceDiagram)
            #expect(viewModel.diagramFormat == .mermaid)
            #expect(viewModel.entryPoint == "Foo.bar")
            #expect(viewModel.sequenceDepth == 5)
            #expect(viewModel.selectedPaths == ["/tmp/Foo.swift"])
            #expect(viewModel.currentScript?.text == "sequenceDiagram\nFoo->>Bar: bar()")
        }
    }

    @Test("deleteHistoryItem removes entity and clears selection")
    func deleteHistoryItemRemovesAndClears() {
        runOnMain {
            let persistence = PersistenceController(inMemory: true)
            let modelContext = persistence.container.mainContext
            let viewModel = DiagramViewModel(persistenceController: persistence)

            let entity = DiagramEntity()
            entity.identifier = UUID()
            entity.timestamp = Date()
            entity.mode = DiagramMode.classDiagram.rawValue
            entity.format = DiagramFormat.plantuml.rawValue
            entity.scriptText = "@startuml\n@enduml"
            entity.name = "Test"
            modelContext.insert(entity)
            try? modelContext.save()

            viewModel.loadHistory()
            #expect(viewModel.history.count == 1)

            viewModel.selectedHistoryItem = entity
            viewModel.deleteHistoryItem(entity)

            #expect(viewModel.history.isEmpty)
            #expect(viewModel.selectedHistoryItem == nil)
        }
    }

    @Test("loadHistory returns entities sorted by timestamp descending")
    func loadHistorySorted() {
        runOnMain {
            let persistence = PersistenceController(inMemory: true)
            let modelContext = persistence.container.mainContext
            let viewModel = DiagramViewModel(persistenceController: persistence)

            for idx in 0..<3 {
                let entity = DiagramEntity()
                entity.identifier = UUID()
                entity.timestamp = Date().addingTimeInterval(TimeInterval(idx * 100))
                entity.mode = DiagramMode.classDiagram.rawValue
                entity.format = DiagramFormat.plantuml.rawValue
                entity.name = "Diagram \(idx)"
                modelContext.insert(entity)
            }
            try? modelContext.save()

            viewModel.loadHistory()
            #expect(viewModel.history.count == 3)
            #expect(viewModel.history[0].name == "Diagram 2")
            #expect(viewModel.history[2].name == "Diagram 0")
        }
    }

    // MARK: - loadDiagram edge cases

    @Test("loadDiagram with dependencyGraph mode restores depsMode from entryPoint")
    func loadDiagramDependencyGraphMode() {
        runOnMain {
            let persistence = PersistenceController(inMemory: true)
            let modelContext = persistence.container.mainContext
            let viewModel = DiagramViewModel(persistenceController: persistence)

            let entity = DiagramEntity()
            entity.identifier = UUID()
            entity.timestamp = Date()
            entity.mode = DiagramMode.dependencyGraph.rawValue
            entity.format = DiagramFormat.plantuml.rawValue
            entity.entryPoint = DepsMode.modules.rawValue
            modelContext.insert(entity)

            viewModel.loadDiagram(entity)

            #expect(viewModel.diagramMode == .dependencyGraph)
            #expect(viewModel.depsMode == .modules)
        }
    }

    @Test("loadDiagram with nil scriptText sets no restoredScript")
    func loadDiagramNilScriptText() {
        runOnMain {
            let persistence = PersistenceController(inMemory: true)
            let modelContext = persistence.container.mainContext
            let viewModel = DiagramViewModel(persistenceController: persistence)

            let entity = DiagramEntity()
            entity.identifier = UUID()
            entity.timestamp = Date()
            entity.mode = DiagramMode.classDiagram.rawValue
            entity.format = DiagramFormat.plantuml.rawValue
            entity.scriptText = nil
            modelContext.insert(entity)

            viewModel.loadDiagram(entity)

            #expect(viewModel.currentScript == nil)
        }
    }

    @Test("loadDiagram with invalid mode string defaults to classDiagram")
    func loadDiagramInvalidMode() {
        runOnMain {
            let persistence = PersistenceController(inMemory: true)
            let modelContext = persistence.container.mainContext
            let viewModel = DiagramViewModel(persistenceController: persistence)

            let entity = DiagramEntity()
            entity.identifier = UUID()
            entity.timestamp = Date()
            entity.mode = "invalid_mode"
            entity.format = "invalid_format"
            modelContext.insert(entity)

            viewModel.loadDiagram(entity)

            #expect(viewModel.diagramMode == .classDiagram)
            #expect(viewModel.diagramFormat == .plantuml)
        }
    }

    @Test("loadDiagram with nil paths does not crash")
    func loadDiagramNilPaths() {
        runOnMain {
            let persistence = PersistenceController(inMemory: true)
            let modelContext = persistence.container.mainContext
            let viewModel = DiagramViewModel(persistenceController: persistence)

            let entity = DiagramEntity()
            entity.identifier = UUID()
            entity.timestamp = Date()
            entity.mode = DiagramMode.classDiagram.rawValue
            entity.paths = nil
            modelContext.insert(entity)

            viewModel.loadDiagram(entity)

            #expect(viewModel.selectedPaths.isEmpty)
        }
    }

    // MARK: - deleteHistoryItem edge cases

    @Test("deleteHistoryItem when item is not the selected one does not clear selection")
    func deleteHistoryItemNotSelected() {
        runOnMain {
            let persistence = PersistenceController(inMemory: true)
            let modelContext = persistence.container.mainContext
            let viewModel = DiagramViewModel(persistenceController: persistence)

            let entity1 = DiagramEntity()
            entity1.identifier = UUID()
            entity1.timestamp = Date()
            entity1.mode = DiagramMode.classDiagram.rawValue
            entity1.name = "Entity1"
            modelContext.insert(entity1)

            let entity2 = DiagramEntity()
            entity2.identifier = UUID()
            entity2.timestamp = Date().addingTimeInterval(100)
            entity2.mode = DiagramMode.classDiagram.rawValue
            entity2.name = "Entity2"
            entity2.scriptText = "@startuml\n@enduml"
            modelContext.insert(entity2)
            try? modelContext.save()

            viewModel.loadHistory()
            viewModel.selectedHistoryItem = entity2
            viewModel.loadDiagram(entity2)

            viewModel.deleteHistoryItem(entity1)

            #expect(viewModel.selectedHistoryItem === entity2)
        }
    }
}
