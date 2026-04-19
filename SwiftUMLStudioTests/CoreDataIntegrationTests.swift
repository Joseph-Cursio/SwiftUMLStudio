//
//  CoreDataIntegrationTests.swift
//  SwiftUMLStudioTests
//
//  SwiftData stack and DiagramEntity persistence integration tests.
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

// MARK: - SwiftData Stack Tests

@Suite("PersistenceController + DiagramEntity Integration")
struct CoreDataIntegrationTests {

    // MARK: Container Loading

    @Test("in-memory container is available")
    func inMemoryContainerLoads() {
        runOnMain {
            let controller = PersistenceController(inMemory: true)
            // SwiftData container is successfully created if we get here
            let context = controller.container.mainContext
            #expect(context != nil)
        }
    }

    // MARK: DiagramEntity CRUD

    @Test("DiagramEntity can be created in an in-memory context")
    func createDiagramEntity() throws {
        try runOnMain {
            let controller = PersistenceController(inMemory: true)
            let modelContext = controller.container.mainContext

            let entity = DiagramEntity()
            entity.identifier = UUID()
            entity.name = "Test Diagram"
            entity.timestamp = Date()
            modelContext.insert(entity)

            #expect(entity.name == "Test Diagram")
        }
    }

    @Test("DiagramEntity can be saved and fetched from context")
    func saveAndFetchDiagramEntity() throws {
        try runOnMain {
            let controller = PersistenceController(inMemory: true)
            let modelContext = controller.container.mainContext

            let entity = DiagramEntity()
            let testID = UUID()
            entity.identifier = testID
            entity.name = "Saved Diagram"
            entity.mode = DiagramMode.classDiagram.rawValue
            entity.format = DiagramFormat.plantuml.rawValue
            entity.timestamp = Date()
            entity.scriptText = "@startuml\nclass Foo\n@enduml"
            modelContext.insert(entity)

            try modelContext.save()

            let descriptor = FetchDescriptor<DiagramEntity>()
            let results = try modelContext.fetch(descriptor)

            #expect(results.count == 1)
            #expect(results.first?.identifier == testID)
            #expect(results.first?.name == "Saved Diagram")
            #expect(results.first?.scriptText == "@startuml\nclass Foo\n@enduml")
        }
    }

    @Test("all DiagramEntity attributes round-trip through save and fetch")
    func allAttributesRoundTrip() throws {
        try runOnMain {
            let controller = PersistenceController(inMemory: true)
            let modelContext = controller.container.mainContext

            let testID = UUID()
            let testDate = Date(timeIntervalSince1970: 1_700_000_000)
            let testPaths = try JSONEncoder().encode(["/path/to/file.swift", "/another/file.swift"])

            let entity = DiagramEntity()
            entity.identifier = testID
            entity.name = "Full Round Trip"
            entity.mode = DiagramMode.sequenceDiagram.rawValue
            entity.format = DiagramFormat.mermaid.rawValue
            entity.entryPoint = "MyClass.myMethod"
            entity.sequenceDepth = 5
            entity.paths = testPaths
            entity.scriptText = "sequenceDiagram\n  A->>B: call"
            entity.timestamp = testDate
            modelContext.insert(entity)

            try modelContext.save()

            let descriptor = FetchDescriptor<DiagramEntity>()
            let results = try modelContext.fetch(descriptor)
            let fetched = try #require(results.first)

            #expect(fetched.identifier == testID)
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
            let modelContext = controller.container.mainContext

            let entity = DiagramEntity()
            entity.identifier = UUID()
            entity.name = "To Delete"
            entity.timestamp = Date()
            modelContext.insert(entity)

            try modelContext.save()

            // Verify it exists
            let descriptor = FetchDescriptor<DiagramEntity>()
            let beforeCount = try modelContext.fetch(descriptor).count
            #expect(beforeCount == 1)

            // Delete
            modelContext.delete(entity)
            try modelContext.save()

            let afterCount = try modelContext.fetch(descriptor).count
            #expect(afterCount == 0)
        }
    }

    @Test("multiple DiagramEntity instances can be saved and fetched")
    func multipleDiagramEntities() throws {
        try runOnMain {
            let controller = PersistenceController(inMemory: true)
            let modelContext = controller.container.mainContext

            for idx in 0..<5 {
                let entity = DiagramEntity()
                entity.identifier = UUID()
                entity.name = "Diagram \(idx)"
                entity.timestamp = Date().addingTimeInterval(TimeInterval(idx))
                modelContext.insert(entity)
            }

            try modelContext.save()

            let descriptor = FetchDescriptor<DiagramEntity>()
            let results = try modelContext.fetch(descriptor)
            #expect(results.count == 5)
        }
    }

    @Test("fetch descriptor can sort by timestamp descending")
    func fetchDescriptorSortsByTimestamp() throws {
        try runOnMain {
            let controller = PersistenceController(inMemory: true)
            let modelContext = controller.container.mainContext

            let now = Date()
            for idx in 0..<3 {
                let entity = DiagramEntity()
                entity.identifier = UUID()
                entity.name = "Diagram \(idx)"
                entity.timestamp = now.addingTimeInterval(TimeInterval(idx * 100))
                modelContext.insert(entity)
            }

            try modelContext.save()

            let descriptor = FetchDescriptor<DiagramEntity>(
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            let results = try modelContext.fetch(descriptor)

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
            let modelContext = controller.container.mainContext

            let entity = DiagramEntity()
            // Only set identifier; leave everything else at defaults/nil
            entity.identifier = UUID()
            modelContext.insert(entity)

            try modelContext.save()

            let descriptor = FetchDescriptor<DiagramEntity>()
            let fetched = try #require(try modelContext.fetch(descriptor).first)

            #expect(fetched.name == nil)
            #expect(fetched.mode == nil)
            #expect(fetched.format == nil)
            #expect(fetched.entryPoint == nil)
            #expect(fetched.sequenceDepth == 0) // Int default
            #expect(fetched.paths == nil)
            #expect(fetched.scriptText == nil)
            #expect(fetched.timestamp == nil)
        }
    }

    // MARK: - PersistenceController Additional Tests

    @Test("two in-memory controllers have independent stores")
    func independentInMemoryStores() throws {
        try runOnMain {
            let controller1 = PersistenceController(inMemory: true)
            let controller2 = PersistenceController(inMemory: true)

            let entity = DiagramEntity()
            entity.identifier = UUID()
            entity.name = "Only in controller1"
            entity.timestamp = Date()
            controller1.container.mainContext.insert(entity)
            try controller1.container.mainContext.save()

            let descriptor = FetchDescriptor<DiagramEntity>()
            let results1 = try controller1.container.mainContext.fetch(descriptor)
            let results2 = try controller2.container.mainContext.fetch(descriptor)

            #expect(results1.count == 1)
            #expect(results2.count == 0)
        }
    }
}
