//
//  ViewModelIntegrationTests.swift
//  SwiftPlantUMLstudioTests
//
//  ViewModel history operations and diagram generation pipeline integration tests.
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

// MARK: - DiagramViewModel History Integration Tests

@Suite("DiagramViewModel History Integration")
struct DiagramViewModelHistoryIntegrationTests {

    @Test("loadHistory returns entities after saving one via the context")
    func loadHistoryAfterSave() throws {
        try runOnMain {
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
    }

    @Test("deleteHistoryItem removes the entity and updates history array")
    func deleteHistoryItem() throws {
        try runOnMain {
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
    }

    @Test("loadHistory returns results sorted by timestamp descending")
    func loadHistorySortOrder() throws {
        try runOnMain {
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
    }

    @Test("loadDiagram restores ViewModel state from a DiagramEntity")
    func loadDiagramRestoresState() throws {
        try runOnMain {
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
    }

    @Test("save() generates a descriptive name and stores it in history")
    func saveGeneratesName() throws {
        try runOnMain {
            let persistence = PersistenceController(inMemory: true)
            let viewModel = DiagramViewModel(persistenceController: persistence)

            viewModel.selectedPaths = ["/Users/joe/Projects/MyApp/Sources/Main.swift"]
            viewModel.diagramMode = .classDiagram

            // Create a fake script so we have something to save
            let entity = DiagramEntity()
            entity.scriptText = "@startuml\n@enduml"
            persistence.container.mainContext.insert(entity)
            viewModel.loadDiagram(entity)

            viewModel.save()
            viewModel.loadHistory()

            let saved = try #require(viewModel.history.first)
            #expect(saved.name == "Main.swift")
            #expect(saved.mode == DiagramMode.classDiagram.rawValue)
        }
    }
}

// MARK: - Diagram Generation Pipeline Integration Tests

@Suite("Diagram Generation Pipeline")
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
    private func waitForGeneration(
        _ viewModel: DiagramViewModel,
        timeout: TimeInterval = 15.0
    ) async throws {
        let deadline = Date.now.addingTimeInterval(timeout)
        while viewModel.isGenerating {
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

        let viewModel = DiagramViewModel(persistenceController: PersistenceController(inMemory: true))
        viewModel.diagramMode = .sequenceDiagram
        viewModel.diagramFormat = .plantuml
        viewModel.entryPoint = "Controller.handleRequest"
        viewModel.selectedPaths = [fixturePath]

        viewModel.generate()
        try await waitForGeneration(viewModel)

        let script = try #require(viewModel.currentScript)
        #expect(script.format == .plantuml)
        #expect(script.text.isEmpty == false)
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

        let viewModel = DiagramViewModel(persistenceController: PersistenceController(inMemory: true))
        viewModel.diagramMode = .dependencyGraph
        viewModel.diagramFormat = .plantuml
        viewModel.depsMode = .modules
        viewModel.selectedPaths = [fixturePath]

        viewModel.generate()
        try await waitForGeneration(viewModel)

        let script = try #require(viewModel.currentScript)
        #expect(script.format == .plantuml)
        #expect(script.text.isEmpty == false)
        #expect(script.text.contains("Foundation"))
        #expect(script.text.contains("Combine"))
    }

    // MARK: Direct ClassDiagramGenerator (no ViewModel, no SourceKit)
    //
    // ClassDiagramGenerator.generateScript calls SourceKitten -> sourcekitd XPC.
    // The Xcode app test runner does not configure the toolchain environment that
    // sourcekitd requires, so the XPC connection hangs indefinitely (no crash --
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

        let persistence = PersistenceController(inMemory: true)
        let viewModel = DiagramViewModel(persistenceController: persistence)
        viewModel.diagramMode = .sequenceDiagram
        viewModel.diagramFormat = .plantuml
        viewModel.entryPoint = "Alpha.go"
        viewModel.selectedPaths = [fixturePath]

        viewModel.generate()
        try await waitForGeneration(viewModel)

        // After generation, history should have at least one entry
        #expect(viewModel.history.count >= 1)
        let latest = try #require(viewModel.history.first)
        #expect(latest.mode == DiagramMode.sequenceDiagram.rawValue)
        #expect(latest.format == DiagramFormat.plantuml.rawValue)
    }
}
