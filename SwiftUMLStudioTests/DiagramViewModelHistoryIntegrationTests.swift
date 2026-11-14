//  ViewModel history operations and diagram generation pipeline integration tests.

import Foundation
import SwiftData
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio
import Testing

// MARK: - DiagramViewModel History Integration Tests

@Suite("DiagramViewModel History Integration") @MainActor
struct DiagramViewModelHistoryIntegrationTests {

    @Test("loadHistory returns entities after saving one via the context")
    func loadHistoryAfterSave() throws {
        let persistence = PersistenceController(inMemory: true)
        let modelContext = persistence.container.mainContext

        let entity = DiagramEntity()
        entity.identifier = UUID()
        entity.name = "History Test"
        entity.mode = DiagramMode.classDiagram.rawValue
        entity.format = DiagramFormat.plantuml.rawValue
        entity.timestamp = Date()
        entity.scriptText = "@startuml\nclass A\n@enduml"
        modelContext.insert(entity)
        try modelContext.save()

        let viewModel = DiagramViewModel(persistenceController: persistence)
        viewModel.loadHistory()

        #expect(viewModel.history.count >= 1)
        #expect(viewModel.history.contains { $0.name == "History Test" })
    }

    @Test("deleteHistoryItem removes the entity and updates history array")
    func deleteHistoryItem() throws {
        let persistence = PersistenceController(inMemory: true)
        let modelContext = persistence.container.mainContext

        let entity = DiagramEntity()
        entity.identifier = UUID()
        entity.name = "To Be Deleted"
        entity.mode = DiagramMode.classDiagram.rawValue
        entity.timestamp = Date()
        modelContext.insert(entity)
        try modelContext.save()

        let viewModel = DiagramViewModel(persistenceController: persistence)
        viewModel.loadHistory()

        let entityToDelete = try #require(viewModel.history.first { $0.name == "To Be Deleted" })
        viewModel.deleteHistoryItem(entityToDelete)

        #expect(viewModel.history.contains { $0.name == "To Be Deleted" } == false)

        let descriptor = FetchDescriptor<DiagramEntity>()
        let remaining = try modelContext.fetch(descriptor)
        #expect(remaining.contains { $0.name == "To Be Deleted" } == false)
    }

    @Test("loadHistory returns results sorted by timestamp descending")
    func loadHistorySortOrder() throws {
        let persistence = PersistenceController(inMemory: true)
        let modelContext = persistence.container.mainContext
        let now = Date()

        for idx in 0..<3 {
            let entity = DiagramEntity()
            entity.identifier = UUID()
            entity.name = "Ordered \(idx)"
            entity.mode = DiagramMode.classDiagram.rawValue
            entity.timestamp = now.addingTimeInterval(TimeInterval(idx * 100))
            modelContext.insert(entity)
        }
        try modelContext.save()

        let viewModel = DiagramViewModel(persistenceController: persistence)
        viewModel.loadHistory()

        let orderedNames = viewModel.history.map { $0.name ?? "" }
        #expect(orderedNames == ["Ordered 2", "Ordered 1", "Ordered 0"])
    }

    @Test("loadDiagram restores ViewModel state from a DiagramEntity")
    func loadDiagramRestoresState() throws {
        let persistence = PersistenceController(inMemory: true)
        let modelContext = persistence.container.mainContext

        // Test sequence diagram restoration
        let seqEntity = DiagramEntity()
        seqEntity.identifier = UUID()
        seqEntity.mode = DiagramMode.sequenceDiagram.rawValue
        seqEntity.entryPoint = "Foo.bar"
        seqEntity.timestamp = Date()
        modelContext.insert(seqEntity)

        // Test dependency graph restoration (uses entryPoint for depsMode)
        let depsEntity = DiagramEntity()
        depsEntity.identifier = UUID()
        depsEntity.mode = DiagramMode.dependencyGraph.rawValue
        depsEntity.entryPoint = DepsMode.modules.rawValue
        depsEntity.timestamp = Date()
        modelContext.insert(depsEntity)

        try modelContext.save()

        let viewModel = DiagramViewModel(persistenceController: persistence)

        // Verify sequence restoration
        viewModel.loadDiagram(seqEntity)
        #expect(viewModel.diagramMode == .sequenceDiagram)
        #expect(viewModel.entryPoint == "Foo.bar")

        // Verify dependency restoration
        viewModel.loadDiagram(depsEntity)
        #expect(viewModel.diagramMode == .dependencyGraph)
        #expect(viewModel.depsMode == .modules)
    }

    @Test("save() generates a descriptive name and stores it in history")
    func saveGeneratesName() throws {
        let persistence = PersistenceController(inMemory: true)
        let viewModel = DiagramViewModel(persistenceController: persistence)

        // Create a fake script so we have something to save. `loadDiagram`
        // restores selection/mode from the entity, so it has to run before the
        // state under test is applied — otherwise it overwrites it.
        let entity = DiagramEntity()
        entity.scriptText = "@startuml\n@enduml"
        persistence.container.mainContext.insert(entity)
        viewModel.loadDiagram(entity)

        viewModel.selectedPaths = ["/Users/joe/Projects/MyApp/Sources/Main.swift"]
        viewModel.diagramMode = .classDiagram

        viewModel.save()
        viewModel.loadHistory()

        let saved = try #require(viewModel.history.first)
        #expect(saved.name == "Main.swift")
        #expect(saved.mode == DiagramMode.classDiagram.rawValue)
    }
}
