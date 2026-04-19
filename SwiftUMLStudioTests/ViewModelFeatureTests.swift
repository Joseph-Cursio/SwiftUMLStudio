//
//  ViewModelFeatureTests.swift
//  SwiftUMLStudioTests
//
//  Integration tests for diagram generation and file browser features.
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

// MARK: - DiagramViewModel Integration Tests

@Suite("DiagramViewModel Integration")
struct DiagramViewModelIntegrationTests {

    // MARK: Helpers

    /// Writes `source` to a fresh temp directory and returns the directory URL.
    private func makeFixtureDir(writing source: String) throws -> URL {
        let dir = FileManager.default
            .temporaryDirectory
            .appending(path: "SwiftUMLStudioTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try source.write(to: dir.appending(path: "Fixture.swift"), atomically: true, encoding: .utf8)
        return dir
    }

    /// Polls `viewModel.isGenerating` on the main actor until it becomes false or the timeout elapses.
    @MainActor
    private func waitForGeneration(
        _ viewModel: DiagramViewModel,
        timeout: TimeInterval = 10.0
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

    // MARK: Class Diagram
    //
    // ClassDiagramGenerator uses SyntaxStructure.create(from:), which loads sourcekitd via
    // SourceKitten's Loader.load(path:). The Xcode app test runner does not set up the
    // toolchain environment that sourcekitd requires, so these tests crash with an
    // assertionFailure inside library_wrapper_SourceKit.swift.
    //
    // The SourceKit-based generation pipeline is covered by ClassDiagramGeneratorTests in
    // the SwiftUMLBridgeFramework package test suite (run via `swift test`), where the
    // toolchain environment is configured correctly.

    // MARK: Sequence Diagram
    //
    // SequenceDiagramGenerator uses SwiftSyntax's pure Swift parser (CallGraphExtractor),
    // NOT SourceKit. These tests run fine in the Xcode test host.

    @Test("generateSequenceDiagram produces a script with the entry point in the title")
    @MainActor
    func generateSequenceDiagramPlantUML() async throws {
        let dir = try makeFixtureDir(writing: """
            class Orchestrator {
                func run() {
                    helper.process()
                }
                let helper = Helper()
            }
            class Helper {
                func process() {}
            }
            """)
        defer { try? FileManager.default.removeItem(at: dir) }

        let viewModel = DiagramViewModel(persistenceController: PersistenceController(inMemory: true))
        viewModel.diagramMode = .sequenceDiagram
        viewModel.diagramFormat = .plantuml
        viewModel.entryPoint = "Orchestrator.run"
        viewModel.selectedPaths = [dir.path()]

        viewModel.generate()
        #expect(viewModel.isGenerating == true)
        try await waitForGeneration(viewModel)

        let script = try #require(viewModel.currentScript)
        #expect(script.format == .plantuml)
        #expect(script.text.contains("@startuml"))
        #expect(script.text.contains("@enduml"))
        #expect(script.text.contains("Orchestrator.run"))
    }

    @Test("generateSequenceDiagram produces a Mermaid script with the entry point")
    @MainActor
    func generateSequenceDiagramMermaid() async throws {
        let dir = try makeFixtureDir(writing: """
            class Orchestrator {
                func run() {
                    helper.process()
                }
                let helper = Helper()
            }
            class Helper {
                func process() {}
            }
            """)
        defer { try? FileManager.default.removeItem(at: dir) }

        let viewModel = DiagramViewModel(persistenceController: PersistenceController(inMemory: true))
        viewModel.diagramMode = .sequenceDiagram
        viewModel.diagramFormat = .mermaid
        viewModel.entryPoint = "Orchestrator.run"
        viewModel.selectedPaths = [dir.path()]

        viewModel.generate()
        try await waitForGeneration(viewModel)

        let script = try #require(viewModel.currentScript)
        #expect(script.format == .mermaid)
        #expect(script.text.contains("sequenceDiagram"))
        #expect(script.text.contains("Orchestrator.run"))
    }

    // MARK: Dependency Graph
    //
    // DependencyGraphGenerator in .modules mode uses ImportExtractor (plain string parsing,
    // no SourceKit). The .types mode DOES use SourceKit and hangs in the Xcode test host.

    @Test("generateDependencyGraph (modules) produces a script containing imported module names")
    @MainActor
    func generateDependencyGraphModules() async throws {
        let dir = try makeFixtureDir(writing: """
            import Foundation
            import Combine
            struct MyModel {}
            """)
        defer { try? FileManager.default.removeItem(at: dir) }

        let viewModel = DiagramViewModel(persistenceController: PersistenceController(inMemory: true))
        viewModel.diagramMode = .dependencyGraph
        viewModel.diagramFormat = .plantuml
        viewModel.depsMode = .modules
        viewModel.selectedPaths = [dir.path()]

        viewModel.generate()
        try await waitForGeneration(viewModel)

        let script = try #require(viewModel.currentScript)
        #expect(script.format == .plantuml)
        #expect(script.text.contains("@startuml"))
        #expect(script.text.contains("Foundation"))
    }
}

// MARK: - DiagramViewModel FileBrowser Tests

@Suite("DiagramViewModel FileBrowser")
struct DiagramViewModelFileBrowserTests {

    @Test("rebuildFileTree populates fileTree from selectedPaths")
    func rebuildFileTreePopulates() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "VMFileBrowser-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "struct Foo {}".write(to: dir.appending(path: "Foo.swift"), atomically: true, encoding: .utf8)

        runOnMain {
            let viewModel = DiagramViewModel(persistenceController: PersistenceController(inMemory: true))
            viewModel.selectedPaths = [dir.path()]
            viewModel.rebuildFileTree()
            #expect(viewModel.fileTree.isEmpty == false)
        }
    }

    @Test("rebuildFileTree auto-selects first file")
    func rebuildFileTreeAutoSelects() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "VMFileBrowser-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "struct A {}".write(to: dir.appending(path: "A.swift"), atomically: true, encoding: .utf8)

        runOnMain {
            let viewModel = DiagramViewModel(persistenceController: PersistenceController(inMemory: true))
            viewModel.selectedPaths = [dir.path()]
            viewModel.rebuildFileTree()
            #expect(viewModel.selectedFileURL != nil)
            #expect(viewModel.selectedFileContent.isEmpty == false)
        }
    }

    @Test("selectFile loads content")
    func selectFileLoadsContent() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "VMFileBrowser-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "Test.swift")
        try "struct Test {}".write(to: file, atomically: true, encoding: .utf8)

        runOnMain {
            let viewModel = DiagramViewModel(persistenceController: PersistenceController(inMemory: true))
            viewModel.selectFile(file)
            #expect(viewModel.selectedFileContent == "struct Test {}")
            #expect(viewModel.selectedFileURL == file)
        }
    }

    @Test("selectFile with nil clears content")
    func selectFileNilClears() {
        runOnMain {
            let viewModel = DiagramViewModel(persistenceController: PersistenceController(inMemory: true))
            viewModel.selectedFileContent = "old content"
            viewModel.selectFile(nil)
            #expect(viewModel.selectedFileContent.isEmpty)
            #expect(viewModel.selectedFileURL == nil)
        }
    }

    @Test("rebuildFileTree clears selection when file no longer in paths")
    func rebuildFileTreeClearsStaleSelection() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "VMFileBrowser-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "Gone.swift")
        try "struct Gone {}".write(to: file, atomically: true, encoding: .utf8)

        runOnMain {
            let viewModel = DiagramViewModel(persistenceController: PersistenceController(inMemory: true))
            viewModel.selectedPaths = [dir.path()]
            viewModel.rebuildFileTree()
            #expect(viewModel.selectedFileURL != nil)

            // Remove the file and rebuild with empty paths
            viewModel.selectedPaths = []
            viewModel.rebuildFileTree()
            #expect(viewModel.selectedFileURL == nil)
            #expect(viewModel.selectedFileContent.isEmpty)
        }
    }
}
