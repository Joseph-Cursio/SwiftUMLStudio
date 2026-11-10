//  ViewModel history operations and diagram generation pipeline integration tests.

import Foundation
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio
import Testing

// MARK: - Diagram Generation Pipeline Integration Tests

@Suite("Diagram Generation Pipeline") @MainActor
struct DiagramGenerationPipelineTests {

    // MARK: Helpers

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
