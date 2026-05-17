//
//  DiagramViewModelHistoryTests.swift
//  SwiftUMLStudioTests
//
//  Unit tests for DiagramViewModel history operations: save, load, delete, and edge cases.
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

private func runOnMain(_ block: @MainActor () throws -> Void) throws {
    if Thread.isMainThread {
        try MainActor.assumeIsolated(block)
    } else {
        var thrownError: (any Error)?
        DispatchQueue.main.sync {
            do { try MainActor.assumeIsolated(block) } catch { thrownError = error }
        }
        if let err = thrownError { throw err }
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

    @Test("loadDiagram restores state machine identifier from entity")
    func loadDiagramRestoresStateMachine() {
        runOnMain {
            let persistence = PersistenceController(inMemory: true)
            let modelContext = persistence.container.mainContext
            let viewModel = DiagramViewModel(persistenceController: persistence)

            let entity = DiagramEntity()
            entity.identifier = UUID()
            entity.timestamp = Date()
            entity.mode = DiagramMode.stateMachine.rawValue
            entity.format = DiagramFormat.plantuml.rawValue
            entity.entryPoint = "TrafficLight.Light"
            entity.scriptText = "@startuml\ntitle TrafficLight.Light\n@enduml"
            entity.paths = try? JSONEncoder().encode(["/tmp/Foo.swift"])
            modelContext.insert(entity)

            viewModel.loadDiagram(entity)

            #expect(viewModel.diagramMode == .stateMachine)
            #expect(viewModel.stateIdentifier == "TrafficLight.Light")
            #expect(viewModel.currentScript?.text.contains("TrafficLight.Light") == true)
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

    // MARK: - Bookmark restoration

    @Test("loadDiagram restores paths from security-scoped bookmarks when present")
    func loadDiagramResolvesBookmarks() throws {
        try runOnMain {
            let persistence = PersistenceController(inMemory: true)
            let viewModel = DiagramViewModel(persistenceController: persistence)

            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("SUS-load-bookmark-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let bookmark = try #require(SecurityScopedURL.makeBookmark(for: directory))

            let entity = DiagramEntity()
            entity.identifier = UUID()
            entity.timestamp = Date()
            entity.mode = DiagramMode.classDiagram.rawValue
            entity.format = DiagramFormat.plantuml.rawValue
            entity.paths = try JSONEncoder().encode(["/tmp/stale-fallback"])
            entity.pathBookmarks = try JSONEncoder().encode([Data?.some(bookmark)])

            viewModel.loadDiagram(entity)

            // Path comparison via standardized URLs: macOS resolves `/var` to
            // `/private/var`, so the literal strings may differ even when both
            // point at the same on-disk location.
            #expect(viewModel.selectedPaths.count == 1)
            let restoredURL = URL(fileURLWithPath: viewModel.selectedPaths[0])
            #expect(restoredURL.standardizedFileURL == directory.standardizedFileURL)
            #expect(viewModel.selectedPathBookmarks.count == 1)
            #expect(viewModel.selectedPathBookmarks.first ?? nil == bookmark)
        }
    }

    @Test("loadDiagram falls back to raw paths when bookmark resolution fails")
    func loadDiagramFallsBackOnGarbageBookmark() throws {
        try runOnMain {
            let persistence = PersistenceController(inMemory: true)
            let viewModel = DiagramViewModel(persistenceController: persistence)

            let entity = DiagramEntity()
            entity.identifier = UUID()
            entity.timestamp = Date()
            entity.mode = DiagramMode.classDiagram.rawValue
            entity.format = DiagramFormat.plantuml.rawValue
            entity.paths = try JSONEncoder().encode(["/tmp/Foo.swift"])
            entity.pathBookmarks = try JSONEncoder().encode([Data?.some(Data([0xDE, 0xAD]))])

            viewModel.loadDiagram(entity)

            #expect(viewModel.selectedPaths == ["/tmp/Foo.swift"])
            #expect(viewModel.selectedPathBookmarks == [nil])
        }
    }

    @Test("loadDiagram on legacy paths-only entity leaves bookmarks empty")
    func loadDiagramLegacyEntity() throws {
        try runOnMain {
            let persistence = PersistenceController(inMemory: true)
            let viewModel = DiagramViewModel(persistenceController: persistence)

            let entity = DiagramEntity()
            entity.identifier = UUID()
            entity.timestamp = Date()
            entity.mode = DiagramMode.classDiagram.rawValue
            entity.format = DiagramFormat.plantuml.rawValue
            entity.paths = try JSONEncoder().encode(["/legacy/path"])
            // No pathBookmarks set.

            viewModel.loadDiagram(entity)

            #expect(viewModel.selectedPaths == ["/legacy/path"])
            #expect(viewModel.selectedPathBookmarks.isEmpty)
        }
    }
}
