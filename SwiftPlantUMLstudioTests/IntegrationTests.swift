//
//  IntegrationTests.swift
//  SwiftPlantUMLstudioTests
//
//  Integration tests covering infrastructure wiring: Core Data stack,
//  DiagramEntity persistence, ViewModel history operations, and the
//  diagram generation pipeline.
//

import CoreData
import Foundation
import Testing
import SwiftUMLBridgeFramework
@testable import SwiftPlantUMLstudio

// MARK: - GCD dispatch helpers
//
// Swift Testing's @MainActor dispatch uses the Swift Concurrency main-actor executor,
// which is broken in the Xcode app-test host on macOS 26 beta. GCD DispatchQueue.main
// bypasses that executor and uses the proven main-queue / run-loop path. See the
// companion comment in SwiftPlantUMLstudioTests.swift for the full explanation.

private func runOnMain(_ block: @MainActor () -> Void) {
    if Thread.isMainThread {
        MainActor.assumeIsolated(block)
        return
    }
    DispatchQueue.main.sync { MainActor.assumeIsolated(block) }
}

private func runOnMain(_ block: @MainActor () throws -> Void) throws {
    if Thread.isMainThread {
        try MainActor.assumeIsolated(block)
        return
    }
    var thrownError: (any Error)?
    DispatchQueue.main.sync {
        do { try MainActor.assumeIsolated(block) } catch { thrownError = error }
    }
    if let err = thrownError { throw err }
}

// MARK: - Core Data Stack Tests

@Suite("PersistenceController + DiagramEntity Integration", .serialized)
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

            for i in 0..<5 {
                let entity = DiagramEntity(context: context)
                entity.id = UUID()
                entity.name = "Diagram \(i)"
                entity.timestamp = Date().addingTimeInterval(TimeInterval(i))
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
            for i in 0..<3 {
                let entity = DiagramEntity(context: context)
                entity.id = UUID()
                entity.name = "Diagram \(i)"
                entity.timestamp = now.addingTimeInterval(TimeInterval(i * 100))
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
}

// MARK: - DiagramViewModel History Integration Tests

@Suite("DiagramViewModel History Integration", .serialized)
struct DiagramViewModelHistoryIntegrationTests {

    @Test("loadHistory returns entities after saving one via the context")
    func loadHistoryAfterSave() throws {
        try runOnMain {
            let pc = PersistenceController(inMemory: true)
            let context = pc.container.viewContext

            let entity = DiagramEntity(context: context)
            entity.id = UUID()
            entity.name = "History Test"
            entity.mode = DiagramMode.classDiagram.rawValue
            entity.format = DiagramFormat.plantuml.rawValue
            entity.timestamp = Date()
            entity.scriptText = "@startuml\nclass A\n@enduml"
            try context.save()

            let vm = DiagramViewModel(persistenceController: pc)
            vm.loadHistory()

            #expect(vm.history.count >= 1)
            #expect(vm.history.contains { $0.name == "History Test" })
        }
    }

    @Test("deleteHistoryItem removes the entity and updates history array")
    func deleteHistoryItem() throws {
        try runOnMain {
            let pc = PersistenceController(inMemory: true)
            let context = pc.container.viewContext

            let entity = DiagramEntity(context: context)
            entity.id = UUID()
            entity.name = "To Be Deleted"
            entity.mode = DiagramMode.classDiagram.rawValue
            entity.timestamp = Date()
            try context.save()

            let vm = DiagramViewModel(persistenceController: pc)
            vm.loadHistory()

            let entityToDelete = try #require(vm.history.first { $0.name == "To Be Deleted" })
            vm.deleteHistoryItem(entityToDelete)

            #expect(!vm.history.contains { $0.name == "To Be Deleted" })

            let request = DiagramEntity.fetchRequest()
            let remaining = try context.fetch(request)
            #expect(!remaining.contains { $0.name == "To Be Deleted" })
        }
    }

    @Test("loadHistory returns results sorted by timestamp descending")
    func loadHistorySortOrder() throws {
        try runOnMain {
            let pc = PersistenceController(inMemory: true)
            let context = pc.container.viewContext
            let now = Date()

            for i in 0..<3 {
                let entity = DiagramEntity(context: context)
                entity.id = UUID()
                entity.name = "Ordered \(i)"
                entity.mode = DiagramMode.classDiagram.rawValue
                entity.timestamp = now.addingTimeInterval(TimeInterval(i * 100))
            }
            try context.save()

            let vm = DiagramViewModel(persistenceController: pc)
            vm.loadHistory()

            let orderedNames = vm.history.map { $0.name ?? "" }
            #expect(orderedNames == ["Ordered 2", "Ordered 1", "Ordered 0"])
        }
    }

    @Test("loadDiagram restores ViewModel state from a DiagramEntity")
    func loadDiagramRestoresState() throws {
        try runOnMain {
            let pc = PersistenceController(inMemory: true)
            let context = pc.container.viewContext

            let entity = DiagramEntity(context: context)
            entity.id = UUID()
            entity.mode = DiagramMode.sequenceDiagram.rawValue
            entity.format = DiagramFormat.mermaid.rawValue
            entity.entryPoint = "Foo.bar"
            entity.sequenceDepth = 7
            entity.paths = try JSONEncoder().encode(["/some/path.swift"])
            entity.timestamp = Date()
            try context.save()

            let vm = DiagramViewModel(persistenceController: pc)
            vm.loadHistory()

            let saved = try #require(vm.history.first)
            vm.loadDiagram(saved)

            #expect(vm.diagramMode == .sequenceDiagram)
            #expect(vm.diagramFormat == .mermaid)
            #expect(vm.entryPoint == "Foo.bar")
            #expect(vm.sequenceDepth == 7)
            #expect(vm.selectedPaths == ["/some/path.swift"])
        }
    }
}

// MARK: - Diagram Generation Pipeline Integration Tests

@Suite("Diagram Generation Pipeline", .serialized)
struct DiagramGenerationPipelineTests {

    // MARK: Helpers

    /// Returns the path to the TestData directory inside SwiftUMLBridge.
    private var testDataDir: String {
        // Resolve relative to the source repository root
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // SwiftPlantUMLstudioTests/
            .deletingLastPathComponent() // SwiftPlantUMLstudio/
        return projectRoot
            .appendingPathComponent("SwiftUMLBridge/Tests/SwiftUMLBridgeFrameworkTests/TestData")
            .path
    }

    /// Creates a temp directory with a single Swift fixture file and returns the directory path.
    private func makeFixtureDir(source: String) throws -> String {
        let dir = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("IntegrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try source.write(
            to: dir.appendingPathComponent("Fixture.swift"),
            atomically: true,
            encoding: .utf8
        )
        return dir.path
    }

    /// Polls the ViewModel until generation completes or timeout.
    @MainActor
    private func waitForGeneration(_ vm: DiagramViewModel, timeout: TimeInterval = 15.0) async throws {
        let deadline = Date.now.addingTimeInterval(timeout)
        while vm.isGenerating {
            guard Date.now < deadline else {
                Issue.record("Generation timed out after \(timeout) seconds")
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    // MARK: Sequence Diagram via ViewModel

    @Test("end-to-end sequence diagram generation from a real Swift file",
          .disabled("sourcekitd hangs in the Xcode test host — run via `swift test` instead"))
    @MainActor
    func sequenceDiagramEndToEnd() async throws {
        let fixturePath = try makeFixtureDir(source: """
            class Controller {
                let service = Service()
                func handleRequest() {
                    service.process()
                }
            }
            class Service {
                func process() {}
            }
            """)
        defer { try? FileManager.default.removeItem(atPath: fixturePath) }

        let vm = DiagramViewModel(persistenceController: PersistenceController(inMemory: true))
        vm.diagramMode = .sequenceDiagram
        vm.diagramFormat = .plantuml
        vm.entryPoint = "Controller.handleRequest"
        vm.selectedPaths = [fixturePath]

        vm.generate()
        try await waitForGeneration(vm)

        let script = try #require(vm.currentScript)
        #expect(script.format == .plantuml)
        #expect(!script.text.isEmpty)
        #expect(script.text.contains("@startuml"))
        #expect(script.text.contains("@enduml"))
        #expect(script.text.contains("Controller.handleRequest"))
    }

    // MARK: Dependency Graph (modules mode) via ViewModel

    @Test("end-to-end dependency graph (modules) generation from a real Swift file",
          .disabled("sourcekitd hangs in the Xcode test host — run via `swift test` instead"))
    @MainActor
    func dependencyGraphModulesEndToEnd() async throws {
        let fixturePath = try makeFixtureDir(source: """
            import Foundation
            import Combine

            struct DataManager {
                func load() {}
            }
            """)
        defer { try? FileManager.default.removeItem(atPath: fixturePath) }

        let vm = DiagramViewModel(persistenceController: PersistenceController(inMemory: true))
        vm.diagramMode = .dependencyGraph
        vm.diagramFormat = .plantuml
        vm.depsMode = .modules
        vm.selectedPaths = [fixturePath]

        vm.generate()
        try await waitForGeneration(vm)

        let script = try #require(vm.currentScript)
        #expect(script.format == .plantuml)
        #expect(!script.text.isEmpty)
        #expect(script.text.contains("Foundation"))
        #expect(script.text.contains("Combine"))
    }

    // MARK: Direct ClassDiagramGenerator (no ViewModel, no SourceKit)
    //
    // ClassDiagramGenerator.generateScript calls SourceKitten → sourcekitd XPC.
    // The Xcode app test runner does not configure the toolchain environment that
    // sourcekitd requires, so the XPC connection hangs indefinitely (no crash —
    // just a frozen await). Covered by ClassDiagramGeneratorTests in the
    // SwiftUMLBridgeFramework package test suite (`swift test`).

    @Test("ClassDiagramGenerator.generateScript produces valid output for Swift source",
          .disabled("sourcekitd hangs in the Xcode test host — run via `swift test` instead"))
    func classDiagramGeneratorDirectInvocation() async throws {
        let fixturePath = try makeFixtureDir(source: """
            class Animal {
                var name: String = ""
                func speak() -> String { return name }
            }
            class Dog: Animal {
                override func speak() -> String { return "Woof" }
            }
            """)
        defer { try? FileManager.default.removeItem(atPath: fixturePath) }

        var config = Configuration.default
        config.format = .plantuml

        let script = await Task.detached {
            ClassDiagramGenerator().generateScript(for: [fixturePath], with: config)
        }.value

        // The script is always returned (non-optional), but may have minimal content
        // if SourceKit is unavailable in the Xcode test host environment.
        #expect(script.format == .plantuml)
        #expect(script.text.contains("@startuml"))
        #expect(script.text.contains("@enduml"))
    }

    // MARK: Generation saves to history

    @Test("successful generation saves a history entry via the ViewModel",
          .disabled("sourcekitd hangs in the Xcode test host — run via `swift test` instead"))
    @MainActor
    func generationSavesToHistory() async throws {
        let fixturePath = try makeFixtureDir(source: """
            class Alpha {
                let beta = Beta()
                func go() { beta.run() }
            }
            class Beta {
                func run() {}
            }
            """)
        defer { try? FileManager.default.removeItem(atPath: fixturePath) }

        let pc = PersistenceController(inMemory: true)
        let vm = DiagramViewModel(persistenceController: pc)
        vm.diagramMode = .sequenceDiagram
        vm.diagramFormat = .plantuml
        vm.entryPoint = "Alpha.go"
        vm.selectedPaths = [fixturePath]

        vm.generate()
        try await waitForGeneration(vm)

        // After generation, history should have at least one entry
        #expect(vm.history.count >= 1)
        let latest = try #require(vm.history.first)
        #expect(latest.mode == DiagramMode.sequenceDiagram.rawValue)
        #expect(latest.format == DiagramFormat.plantuml.rawValue)
    }
}
