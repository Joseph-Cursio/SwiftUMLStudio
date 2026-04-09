//
//  CoreDataIntegrationTests.swift
//  SwiftPlantUMLstudioTests
//
//  Core Data stack and DiagramEntity persistence integration tests.
//

import CoreData
import Foundation
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

// MARK: - Core Data Stack Tests

@Suite("PersistenceController + DiagramEntity Integration")
struct CoreDataIntegrationTests {

    // MARK: Helpers

    // MARK: Container Loading

    @Test("in-memory container loads persistent stores without error")
    func inMemoryContainerLoads() {
        runOnMain {
            let controller = PersistenceController(inMemory: true)
            let stores = controller.container.persistentStoreCoordinator.persistentStores
            #expect(stores.count > 0, "Expected at least one persistent store to be loaded")
        }
    }

    @Test("in-memory container uses /dev/null store URL")
    func inMemoryContainerUsesDevNull() {
        runOnMain {
            let controller = PersistenceController(inMemory: true)
            let stores = controller.container.persistentStoreCoordinator.persistentStores
            let url = stores.first?.url
            #expect(url == URL(fileURLWithPath: "/dev/null"))
        }
    }

    @Test("viewContext is available and has merge policy set")
    func viewContextConfigured() {
        runOnMain {
            let controller = PersistenceController(inMemory: true)
            let context = controller.container.viewContext
            #expect(context.automaticallyMergesChangesFromParent == true)
            #expect(context.mergePolicy is NSMergePolicy)
        }
    }

    // MARK: DiagramEntity CRUD

    @Test("DiagramEntity can be created in an in-memory context")
    func createDiagramEntity() throws {
        try runOnMain {
            let controller = PersistenceController(inMemory: true)
            let context = controller.container.viewContext

            let entity = DiagramEntity(context: context)
            entity.id = UUID()
            entity.name = "Test Diagram"
            entity.timestamp = Date()

            #expect(entity.name == "Test Diagram")
            #expect(entity.id != nil)
        }
    }

    @Test("DiagramEntity can be saved and fetched from context")
    func saveAndFetchDiagramEntity() throws {
        try runOnMain {
            let controller = PersistenceController(inMemory: true)
            let context = controller.container.viewContext

            let entity = DiagramEntity(context: context)
            let testID = UUID()
            entity.id = testID
            entity.name = "Saved Diagram"
            entity.mode = DiagramMode.classDiagram.rawValue
            entity.format = DiagramFormat.plantuml.rawValue
            entity.timestamp = Date()
            entity.scriptText = "@startuml\nclass Foo\n@enduml"

            try context.save()

            let request = DiagramEntity.fetchRequest()
            let results = try context.fetch(request)

            #expect(results.count == 1)
            #expect(results.first?.id == testID)
            #expect(results.first?.name == "Saved Diagram")
            #expect(results.first?.scriptText == "@startuml\nclass Foo\n@enduml")
        }
    }

    @Test("all DiagramEntity attributes round-trip through save and fetch")
    func allAttributesRoundTrip() throws {
        try runOnMain {
            let controller = PersistenceController(inMemory: true)
            let context = controller.container.viewContext

            let testID = UUID()
            let testDate = Date(timeIntervalSince1970: 1_700_000_000)
            let testPaths = try JSONEncoder().encode(["/path/to/file.swift", "/another/file.swift"])

            let entity = DiagramEntity(context: context)
            entity.id = testID
            entity.name = "Full Round Trip"
            entity.mode = DiagramMode.sequenceDiagram.rawValue
            entity.format = DiagramFormat.mermaid.rawValue
            entity.entryPoint = "MyClass.myMethod"
            entity.sequenceDepth = 5
            entity.paths = testPaths
            entity.scriptText = "sequenceDiagram\n  A->>B: call"
            entity.timestamp = testDate

            try context.save()

            // Clear the context cache to force a fetch from the store
            context.reset()

            let request = DiagramEntity.fetchRequest()
            let results = try context.fetch(request)
            let fetched = try #require(results.first)

            #expect(fetched.id == testID)
            #expect(fetched.name == "Full Round Trip")
            #expect(fetched.mode == "Sequence Diagram")
            #expect(fetched.format == "mermaid")
            #expect(fetched.entryPoint == "MyClass.myMethod")
            #expect(fetched.sequenceDepth == 5)
            #expect(fetched.paths == testPaths)
            #expect(fetched.scriptText == "sequenceDiagram\n  A->>B: call")
            #expect(fetched.timestamp == testDate)
        }
    }

    @Test("DiagramEntity can be deleted from context")
    func deleteDiagramEntity() throws {
        try runOnMain {
            let controller = PersistenceController(inMemory: true)
            let context = controller.container.viewContext

            let entity = DiagramEntity(context: context)
            entity.id = UUID()
            entity.name = "To Delete"
            entity.timestamp = Date()

            try context.save()

            // Verify it exists
            let request = DiagramEntity.fetchRequest()
            let beforeCount = try context.fetch(request).count
            #expect(beforeCount == 1)

            // Delete
            context.delete(entity)
            try context.save()

            let afterCount = try context.fetch(request).count
            #expect(afterCount == 0)
        }
    }

    @Test("multiple DiagramEntity instances can be saved and fetched")
    func multipleDiagramEntities() throws {
        try runOnMain {
            let controller = PersistenceController(inMemory: true)
            let context = controller.container.viewContext

            for idx in 0..<5 {
                let entity = DiagramEntity(context: context)
                entity.id = UUID()
                entity.name = "Diagram \(idx)"
                entity.timestamp = Date().addingTimeInterval(TimeInterval(idx))
            }

            try context.save()

            let request = DiagramEntity.fetchRequest()
            let results = try context.fetch(request)
            #expect(results.count == 5)
        }
    }

    @Test("fetch request can sort by timestamp descending")
    func fetchRequestSortsByTimestamp() throws {
        try runOnMain {
            let controller = PersistenceController(inMemory: true)
            let context = controller.container.viewContext

            let now = Date()
            for idx in 0..<3 {
                let entity = DiagramEntity(context: context)
                entity.id = UUID()
                entity.name = "Diagram \(idx)"
                entity.timestamp = now.addingTimeInterval(TimeInterval(idx * 100))
            }

            try context.save()

            let request = NSFetchRequest<DiagramEntity>(entityName: "DiagramEntity")
            request.sortDescriptors = [NSSortDescriptor(keyPath: \DiagramEntity.timestamp, ascending: false)]
            let results = try context.fetch(request)

            #expect(results.count == 3)
            // Most recent first
            #expect(results[0].name == "Diagram 2")
            #expect(results[1].name == "Diagram 1")
            #expect(results[2].name == "Diagram 0")
        }
    }

    @Test("DiagramEntity with nil optional attributes saves and fetches successfully")
    func nilAttributesRoundTrip() throws {
        try runOnMain {
            let controller = PersistenceController(inMemory: true)
            let context = controller.container.viewContext

            let entity = DiagramEntity(context: context)
            // Only set required-ish fields; leave everything else nil
            entity.id = UUID()

            try context.save()
            context.reset()

            let request = DiagramEntity.fetchRequest()
            let fetched = try #require(try context.fetch(request).first)

            #expect(fetched.name == nil)
            #expect(fetched.mode == nil)
            #expect(fetched.format == nil)
            #expect(fetched.entryPoint == nil)
            #expect(fetched.sequenceDepth == 0) // Int16 default
            #expect(fetched.paths == nil)
            #expect(fetched.scriptText == nil)
            #expect(fetched.timestamp == nil)
        }
    }

    // MARK: - PersistenceController Additional Tests

    @Test("shared static model is the same instance across calls")
    func managedObjectModelIsSingleton() {
        runOnMain {
            let model1 = PersistenceController.managedObjectModel
            let model2 = PersistenceController.managedObjectModel
            #expect(model1 === model2)
        }
    }

    @Test("managed object model contains DiagramEntity entity description")
    func modelContainsDiagramEntity() {
        runOnMain {
            let model = PersistenceController.managedObjectModel
            let entityNames = model.entities.map(\.name)
            #expect(entityNames.contains("DiagramEntity"))
        }
    }

    @Test("managed object model contains ProjectSnapshot entity description")
    func modelContainsProjectSnapshot() {
        runOnMain {
            let model = PersistenceController.managedObjectModel
            let entityNames = model.entities.map(\.name)
            #expect(entityNames.contains("ProjectSnapshot"))
        }
    }

    @Test("two in-memory controllers have independent stores")
    func independentInMemoryStores() throws {
        try runOnMain {
            let controller1 = PersistenceController(inMemory: true)
            let controller2 = PersistenceController(inMemory: true)

            let entity = DiagramEntity(context: controller1.container.viewContext)
            entity.id = UUID()
            entity.name = "Only in controller1"
            entity.timestamp = Date()
            try controller1.container.viewContext.save()

            let request = DiagramEntity.fetchRequest()
            let results1 = try controller1.container.viewContext.fetch(request)
            let results2 = try controller2.container.viewContext.fetch(request)

            #expect(results1.count == 1)
            #expect(results2.count == 0)
        }
    }

    @Test("viewContext merge policy is mergeByPropertyObjectTrump")
    func viewContextMergePolicy() {
        runOnMain {
            let controller = PersistenceController(inMemory: true)
            let policy = controller.container.viewContext.mergePolicy as? NSMergePolicy
            #expect(policy === NSMergePolicy.mergeByPropertyObjectTrump)
        }
    }

    @Test("in-memory store description URL is /dev/null")
    func inMemoryStoreDescription() {
        runOnMain {
            let controller = PersistenceController(inMemory: true)
            let desc = controller.container.persistentStoreDescriptions.first
            #expect(desc?.url == URL(fileURLWithPath: "/dev/null"))
        }
    }
}
