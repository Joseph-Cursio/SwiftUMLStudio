//
//  SwiftPlantUMLstudioTests.swift
//  SwiftPlantUMLstudioTests
//
//  Created by joe cursio on 2/26/26.
//

import CoreData
import Foundation
import Testing
import SwiftUMLBridgeFramework
@testable import SwiftPlantUMLstudio

// MARK: - GCD dispatch helpers
//
// Swift Testing's @MainActor dispatch uses the Swift Concurrency main-actor executor,
// which is broken in the Xcode app-test host on macOS 26 beta (same root cause as the
// SerialExecutor.isMainExecutor.getter null-pointer crash). GCD DispatchQueue.main.sync
// bypasses that executor and uses the proven main-queue / run-loop path that XCTest itself
// relies on. MainActor.assumeIsolated() is safe here because it checks Thread.isMainThread
// (an Objective-C concept), not isMainExecutor.

/// Run `block` synchronously on the main thread with `@MainActor` isolation (non-throwing).
private func runOnMain(_ block: @MainActor () -> Void) {
    if Thread.isMainThread {
        MainActor.assumeIsolated(block)
    } else {
        DispatchQueue.main.sync { MainActor.assumeIsolated(block) }
    }
}

/// Run `block` synchronously on the main thread with `@MainActor` isolation (throwing).
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

// MARK: - DiagramMode Tests

@Suite("DiagramMode")
struct DiagramModeTests {

    @Test("has exactly three cases")
    func allCasesCount() {
        runOnMain {
            #expect(DiagramMode.allCases.count == 3)
        }
    }

    @Test("classDiagram raw value is 'Class Diagram'")
    func classDiagramRawValue() {
        #expect(DiagramMode.classDiagram.rawValue == "Class Diagram")
    }

    @Test("sequenceDiagram raw value is 'Sequence Diagram'")
    func sequenceDiagramRawValue() {
        #expect(DiagramMode.sequenceDiagram.rawValue == "Sequence Diagram")
    }

    @Test("dependencyGraph raw value is 'Dependency Graph'")
    func dependencyGraphRawValue() {
        #expect(DiagramMode.dependencyGraph.rawValue == "Dependency Graph")
    }

    @Test("id equals rawValue for all cases")
    func idEqualsRawValue() {
        // DiagramMode.id is @MainActor via default actor isolation; use GCD workaround.
        runOnMain {
            for mode in DiagramMode.allCases {
                #expect(mode.id == mode.rawValue)
            }
        }
    }

    @Test("allCases contains every case")
    func allCasesContainsEverything() {
        let cases = DiagramMode.allCases
        #expect(cases.contains(.classDiagram))
        #expect(cases.contains(.sequenceDiagram))
        #expect(cases.contains(.dependencyGraph))
    }

    @Test("can be initialized from raw value")
    func initFromRawValue() {
        #expect(DiagramMode(rawValue: "Class Diagram") == .classDiagram)
        #expect(DiagramMode(rawValue: "Sequence Diagram") == .sequenceDiagram)
        #expect(DiagramMode(rawValue: "Dependency Graph") == .dependencyGraph)
        #expect(DiagramMode(rawValue: "nonexistent") == nil)
    }
}

// MARK: - DiagramViewModel Tests

@Suite("DiagramViewModel")
struct DiagramViewModelTests {

    // MARK: Default property values

    @Test("default diagramMode is classDiagram")
    func defaultDiagramMode() {
        runOnMain {
            let vm = DiagramViewModel(persistenceController: PersistenceController(inMemory: true))
            #expect(vm.diagramMode == .classDiagram)
        }
    }

    @Test("default diagramFormat is plantuml")
    func defaultDiagramFormat() {
        runOnMain {
            let vm = DiagramViewModel(persistenceController: PersistenceController(inMemory: true))
            #expect(vm.diagramFormat == .plantuml)
        }
    }

    @Test("default depsMode is types")
    func defaultDepsMode() {
        runOnMain {
            let vm = DiagramViewModel(persistenceController: PersistenceController(inMemory: true))
            #expect(vm.depsMode == .types)
        }
    }

    @Test("default sequenceDepth is 3")
    func defaultSequenceDepth() {
        runOnMain {
            let vm = DiagramViewModel(persistenceController: PersistenceController(inMemory: true))
            #expect(vm.sequenceDepth == 3)
        }
    }

    @Test("default entryPoint is empty string")
    func defaultEntryPoint() {
        runOnMain {
            let vm = DiagramViewModel(persistenceController: PersistenceController(inMemory: true))
            #expect(vm.entryPoint == "")
        }
    }

    @Test("default selectedPaths is empty")
    func defaultSelectedPaths() {
        runOnMain {
            let vm = DiagramViewModel(persistenceController: PersistenceController(inMemory: true))
            #expect(vm.selectedPaths.isEmpty)
        }
    }

    @Test("default isGenerating is false")
    func defaultIsGenerating() {
        runOnMain {
            let vm = DiagramViewModel(persistenceController: PersistenceController(inMemory: true))
            #expect(vm.isGenerating == false)
        }
    }

    @Test("default errorMessage is nil")
    func defaultErrorMessage() {
        runOnMain {
            let vm = DiagramViewModel(persistenceController: PersistenceController(inMemory: true))
            #expect(vm.errorMessage == nil)
        }
    }

    // MARK: currentScript

    @Test("currentScript is nil initially for classDiagram mode")
    func currentScriptNilForClassDiagram() {
        runOnMain {
            let vm = DiagramViewModel(persistenceController: PersistenceController(inMemory: true))
            vm.diagramMode = .classDiagram
            #expect(vm.currentScript == nil)
        }
    }

    @Test("currentScript is nil initially for sequenceDiagram mode")
    func currentScriptNilForSequenceDiagram() {
        runOnMain {
            let vm = DiagramViewModel(persistenceController: PersistenceController(inMemory: true))
            vm.diagramMode = .sequenceDiagram
            #expect(vm.currentScript == nil)
        }
    }

    @Test("currentScript is nil initially for dependencyGraph mode")
    func currentScriptNilForDependencyGraph() {
        runOnMain {
            let vm = DiagramViewModel(persistenceController: PersistenceController(inMemory: true))
            vm.diagramMode = .dependencyGraph
            #expect(vm.currentScript == nil)
        }
    }

    // MARK: generate() guard logic
    //
    // generate() sets isGenerating = true synchronously, then spawns a Task on the
    // main-actor executor. On Apple platforms the main-actor executor is backed by
    // DispatchQueue.main, so a subsequent DispatchQueue.main.async block runs AFTER
    // the spawned Task completes, letting us observe the final isGenerating state.

    @Test("generate resets isGenerating when selectedPaths is empty for classDiagram")
    @MainActor
    func generateGuardsEmptyPathsClassDiagram() async {
        let isGenerating = await generateAndWait(mode: .classDiagram, paths: [])
        #expect(isGenerating == false)
    }

    @Test("generate resets isGenerating when selectedPaths is empty for dependencyGraph")
    @MainActor
    func generateGuardsEmptyPathsDependencyGraph() async {
        let isGenerating = await generateAndWait(mode: .dependencyGraph, paths: [])
        #expect(isGenerating == false)
    }

    @Test("generate resets isGenerating when selectedPaths is empty for sequenceDiagram")
    @MainActor
    func generateGuardsEmptyPathsSequenceDiagram() async {
        let isGenerating = await generateAndWait(mode: .sequenceDiagram, paths: [], entryPoint: "Foo.bar")
        #expect(isGenerating == false)
    }

    @Test("generate resets isGenerating for sequenceDiagram with empty entryPoint")
    @MainActor
    func generateGuardsEmptyEntryPoint() async {
        let isGenerating = await generateAndWait(mode: .sequenceDiagram, paths: ["/some/path.swift"], entryPoint: "")
        #expect(isGenerating == false)
    }

    @Test("generate resets isGenerating for sequenceDiagram with malformed entryPoint (no dot)")
    @MainActor
    func generateGuardsMalformedEntryPointNoDot() async {
        let isGenerating = await generateAndWait(mode: .sequenceDiagram, paths: ["/some/path.swift"], entryPoint: "FooBar")
        #expect(isGenerating == false)
    }

    @Test("generate resets isGenerating for sequenceDiagram with too many dots in entryPoint")
    @MainActor
    func generateGuardsMalformedEntryPointTooManyDots() async {
        let isGenerating = await generateAndWait(mode: .sequenceDiagram, paths: ["/some/path.swift"], entryPoint: "Foo.bar.baz")
        #expect(isGenerating == false)
    }

    @Test("refreshEntryPoints clears when no paths selected")
    func refreshEntryPointsClearsWhenNoPathsSelected() {
        runOnMain {
            let vm = DiagramViewModel(persistenceController: PersistenceController(inMemory: true))
            vm.availableEntryPoints = ["Foo.bar"]
            vm.selectedPaths = []
            vm.refreshEntryPoints()
            #expect(vm.availableEntryPoints.isEmpty)
        }
    }
    // MARK: - pathSummary

    @Test("pathSummary with no paths")
    func pathSummaryNoPaths() {
        runOnMain {
            let vm = DiagramViewModel(persistenceController: PersistenceController(inMemory: true))
            #expect(vm.pathSummary == "No source selected")
        }
    }

    @Test("pathSummary with one path shows filename")
    func pathSummaryOnePath() {
        runOnMain {
            let vm = DiagramViewModel(persistenceController: PersistenceController(inMemory: true))
            vm.selectedPaths = ["/Users/test/MyApp/Sources/AppDelegate.swift"]
            #expect(vm.pathSummary == "AppDelegate.swift")
        }
    }

    @Test("pathSummary with multiple paths shows count")
    func pathSummaryMultiplePaths() {
        runOnMain {
            let vm = DiagramViewModel(persistenceController: PersistenceController(inMemory: true))
            vm.selectedPaths = ["/a/First.swift", "/b/Second.swift", "/c/Third.swift"]
            #expect(vm.pathSummary == "First.swift + 2 more")
        }
    }

    // MARK: - save / history

    @Test("save creates a history entity")
    func saveCreatesHistoryEntity() {
        runOnMain {
            let pc = PersistenceController(inMemory: true)
            let vm = DiagramViewModel(persistenceController: pc)
            vm.selectedPaths = ["/tmp/Foo.swift"]
            vm.diagramMode = .classDiagram
            vm.diagramFormat = .plantuml

            // We need a currentScript for save to work.
            // Load a fake history item to set restoredScript.
            let entity = DiagramEntity(context: pc.container.viewContext)
            entity.id = UUID()
            entity.timestamp = Date()
            entity.mode = DiagramMode.classDiagram.rawValue
            entity.format = DiagramFormat.plantuml.rawValue
            entity.scriptText = "@startuml\nclass Foo\n@enduml"
            entity.paths = try? JSONEncoder().encode(["/tmp/Foo.swift"])
            entity.name = "Foo.swift"
            try? pc.container.viewContext.save()

            vm.loadHistory()
            vm.loadDiagram(entity)
            #expect(vm.currentScript != nil)

            let countBefore = vm.history.count
            vm.save()
            #expect(vm.history.count == countBefore + 1)
        }
    }

    @Test("loadDiagram restores all properties from entity")
    func loadDiagramRestoresProperties() {
        runOnMain {
            let pc = PersistenceController(inMemory: true)
            let vm = DiagramViewModel(persistenceController: pc)

            let entity = DiagramEntity(context: pc.container.viewContext)
            entity.id = UUID()
            entity.timestamp = Date()
            entity.mode = DiagramMode.sequenceDiagram.rawValue
            entity.format = DiagramFormat.mermaid.rawValue
            entity.entryPoint = "Foo.bar"
            entity.sequenceDepth = 5
            entity.scriptText = "sequenceDiagram\nFoo->>Bar: bar()"
            entity.paths = try? JSONEncoder().encode(["/tmp/Foo.swift"])

            vm.loadDiagram(entity)

            #expect(vm.diagramMode == .sequenceDiagram)
            #expect(vm.diagramFormat == .mermaid)
            #expect(vm.entryPoint == "Foo.bar")
            #expect(vm.sequenceDepth == 5)
            #expect(vm.selectedPaths == ["/tmp/Foo.swift"])
            #expect(vm.currentScript?.text == "sequenceDiagram\nFoo->>Bar: bar()")
        }
    }

    @Test("deleteHistoryItem removes entity and clears selection")
    func deleteHistoryItemRemovesAndClears() {
        runOnMain {
            let pc = PersistenceController(inMemory: true)
            let vm = DiagramViewModel(persistenceController: pc)

            let entity = DiagramEntity(context: pc.container.viewContext)
            entity.id = UUID()
            entity.timestamp = Date()
            entity.mode = DiagramMode.classDiagram.rawValue
            entity.format = DiagramFormat.plantuml.rawValue
            entity.scriptText = "@startuml\n@enduml"
            entity.name = "Test"
            try? pc.container.viewContext.save()

            vm.loadHistory()
            #expect(vm.history.count == 1)

            vm.selectedHistoryItem = entity
            vm.deleteHistoryItem(entity)

            #expect(vm.history.isEmpty)
            #expect(vm.selectedHistoryItem == nil)
        }
    }

    @Test("loadHistory returns entities sorted by timestamp descending")
    func loadHistorySorted() {
        runOnMain {
            let pc = PersistenceController(inMemory: true)
            let vm = DiagramViewModel(persistenceController: pc)
            let ctx = pc.container.viewContext

            for idx in 0..<3 {
                let entity = DiagramEntity(context: ctx)
                entity.id = UUID()
                entity.timestamp = Date().addingTimeInterval(TimeInterval(idx * 100))
                entity.mode = DiagramMode.classDiagram.rawValue
                entity.format = DiagramFormat.plantuml.rawValue
                entity.name = "Diagram \(idx)"
            }
            try? ctx.save()

            vm.loadHistory()
            #expect(vm.history.count == 3)
            // Most recent first
            #expect(vm.history[0].name == "Diagram 2")
            #expect(vm.history[2].name == "Diagram 0")
        }
    }
}

// MARK: - generate() guard helper
//
// Runs generate() on the main thread, then schedules a follow-up check via a second
// DispatchQueue.main.async. Because the Swift Concurrency main-actor executor enqueues
// its tasks onto DispatchQueue.main (dispatch_async), the spawned Task runs before our
// follow-up block, and we observe the final isGenerating value.

@MainActor
private func generateAndWait(
    mode: DiagramMode,
    paths: [String],
    entryPoint: String = ""
) async -> Bool {
    let vm = DiagramViewModel(persistenceController: PersistenceController(inMemory: true))
    vm.diagramMode = mode
    vm.selectedPaths = paths
    vm.entryPoint = entryPoint
    
    vm.generate()
    
    // Give the Task a moment to start and run its synchronous guard checks.
    // The ViewModel now has a 300ms debounce sleep, so we must wait longer than that.
    try? await Task.sleep(nanoseconds: 400_000_000) // 400ms
    await Task.yield()
    
    return vm.isGenerating
}

// MARK: - DiagramViewModel Integration Tests

@Suite("DiagramViewModel Integration", .serialized)
struct DiagramViewModelIntegrationTests {

    // MARK: Helpers

    /// Writes `source` to a fresh temp directory and returns the directory URL.
    private func makeFixtureDir(writing source: String) throws -> URL {
        let dir = FileManager.default
            .temporaryDirectory
            .appending(path: "SwiftPlantUMLstudioTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try source.write(to: dir.appending(path: "Fixture.swift"), atomically: true, encoding: .utf8)
        return dir
    }

    /// Polls `vm.isGenerating` on the main actor until it becomes false or the timeout elapses.
    @MainActor
    private func waitForGeneration(_ vm: DiagramViewModel, timeout: TimeInterval = 10.0) async throws {
        let deadline = Date.now.addingTimeInterval(timeout)
        while vm.isGenerating {
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

        let vm = DiagramViewModel(persistenceController: PersistenceController(inMemory: true))
        vm.diagramMode = .sequenceDiagram
        vm.diagramFormat = .plantuml
        vm.entryPoint = "Orchestrator.run"
        vm.selectedPaths = [dir.path()]

        vm.generate()
        #expect(vm.isGenerating == true)
        try await waitForGeneration(vm)

        let script = try #require(vm.currentScript)
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

        let vm = DiagramViewModel(persistenceController: PersistenceController(inMemory: true))
        vm.diagramMode = .sequenceDiagram
        vm.diagramFormat = .mermaid
        vm.entryPoint = "Orchestrator.run"
        vm.selectedPaths = [dir.path()]

        vm.generate()
        try await waitForGeneration(vm)

        let script = try #require(vm.currentScript)
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

        let vm = DiagramViewModel(persistenceController: PersistenceController(inMemory: true))
        vm.diagramMode = .dependencyGraph
        vm.diagramFormat = .plantuml
        vm.depsMode = .modules
        vm.selectedPaths = [dir.path()]

        vm.generate()
        try await waitForGeneration(vm)

        let script = try #require(vm.currentScript)
        #expect(script.format == .plantuml)
        #expect(script.text.contains("@startuml"))
        #expect(script.text.contains("Foundation"))
    }
}

// MARK: - FileNode Tests

@Suite("FileNode")
struct FileNodeTests {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "FileNodeTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("buildTree returns empty for empty paths")
    func buildTreeEmpty() {
        runOnMain {
            let tree = FileNode.buildTree(from: [])
            #expect(tree.isEmpty)
        }
    }

    @Test("buildTree returns empty for nonexistent paths")
    func buildTreeNonexistent() {
        runOnMain {
            let tree = FileNode.buildTree(from: ["/nonexistent/path/file.swift"])
            #expect(tree.isEmpty)
        }
    }

    @Test("buildTree returns single file")
    func buildTreeSingleFile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "Hello.swift")
        try "struct Hello {}".write(to: file, atomically: true, encoding: .utf8)

        runOnMain {
            let tree = FileNode.buildTree(from: [file.path()])
            #expect(tree.count == 1)
            #expect(tree[0].name == "Hello.swift")
            #expect(tree[0].isDirectory == false)
            #expect(tree[0].children == nil)
        }
    }

    @Test("buildTree filters out non-swift files in directories")
    func buildTreeFiltersNonSwift() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "struct A {}".write(to: dir.appending(path: "A.swift"), atomically: true, encoding: .utf8)
        try "not swift".write(to: dir.appending(path: "readme.md"), atomically: true, encoding: .utf8)
        try "{}".write(to: dir.appending(path: "config.json"), atomically: true, encoding: .utf8)

        runOnMain {
            let tree = FileNode.buildTree(from: [dir.path()])
            let allURLs = FileNode.allLeafURLs(from: tree)
            #expect(allURLs.count == 1)
            #expect(allURLs[0].lastPathComponent == "A.swift")
        }
    }

    @Test("buildTree creates directory nodes for nested structures")
    func buildTreeNested() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let subdir = dir.appending(path: "Models", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        try "struct A {}".write(to: dir.appending(path: "App.swift"), atomically: true, encoding: .utf8)
        try "struct B {}".write(to: subdir.appending(path: "Model.swift"), atomically: true, encoding: .utf8)

        runOnMain {
            let tree = FileNode.buildTree(from: [dir.path()])
            #expect(tree.count == 2) // Models/ directory + App.swift
            let dirNode = tree.first { $0.isDirectory }
            #expect(dirNode?.name == "Models")
            #expect(dirNode?.children?.count == 1)
            #expect(dirNode?.children?[0].name == "Model.swift")
        }
    }

    @Test("allLeafURLs collects all file URLs from nested tree")
    func allLeafURLsNested() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let subdir = dir.appending(path: "Sub", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        try "struct A {}".write(to: dir.appending(path: "A.swift"), atomically: true, encoding: .utf8)
        try "struct B {}".write(to: subdir.appending(path: "B.swift"), atomically: true, encoding: .utf8)

        runOnMain {
            let tree = FileNode.buildTree(from: [dir.path()])
            let urls = FileNode.allLeafURLs(from: tree)
            #expect(urls.count == 2)
        }
    }
}

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
            let vm = DiagramViewModel(persistenceController: PersistenceController(inMemory: true))
            vm.selectedPaths = [dir.path()]
            vm.rebuildFileTree()
            #expect(!vm.fileTree.isEmpty)
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
            let vm = DiagramViewModel(persistenceController: PersistenceController(inMemory: true))
            vm.selectedPaths = [dir.path()]
            vm.rebuildFileTree()
            #expect(vm.selectedFileURL != nil)
            #expect(!vm.selectedFileContent.isEmpty)
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
            let vm = DiagramViewModel(persistenceController: PersistenceController(inMemory: true))
            vm.selectFile(file)
            #expect(vm.selectedFileContent == "struct Test {}")
            #expect(vm.selectedFileURL == file)
        }
    }

    @Test("selectFile with nil clears content")
    func selectFileNilClears() {
        runOnMain {
            let vm = DiagramViewModel(persistenceController: PersistenceController(inMemory: true))
            vm.selectedFileContent = "old content"
            vm.selectFile(nil)
            #expect(vm.selectedFileContent.isEmpty)
            #expect(vm.selectedFileURL == nil)
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
            let vm = DiagramViewModel(persistenceController: PersistenceController(inMemory: true))
            vm.selectedPaths = [dir.path()]
            vm.rebuildFileTree()
            #expect(vm.selectedFileURL != nil)

            // Remove the file and rebuild with empty paths
            vm.selectedPaths = []
            vm.rebuildFileTree()
            #expect(vm.selectedFileURL == nil)
            #expect(vm.selectedFileContent.isEmpty)
        }
    }
}

@Suite("MermaidHTMLBuilder")
struct MermaidHTMLBuilderTests {

    // MARK: htmlEscape

    @Test("htmlEscape leaves plain text unchanged")
    func htmlEscapePlainText() {
        #expect(MermaidHTMLBuilder.htmlEscape("hello world") == "hello world")
    }

    @Test("htmlEscape replaces & with &amp;")
    func htmlEscapeAmpersand() {
        #expect(MermaidHTMLBuilder.htmlEscape("A & B") == "A &amp; B")
    }

    @Test("htmlEscape replaces < with &lt;")
    func htmlEscapeLessThan() {
        #expect(MermaidHTMLBuilder.htmlEscape("a < b") == "a &lt; b")
    }

    @Test("htmlEscape replaces > with &gt;")
    func htmlEscapeGreaterThan() {
        #expect(MermaidHTMLBuilder.htmlEscape("a > b") == "a &gt; b")
    }

    @Test("htmlEscape replaces all three characters in one string")
    func htmlEscapeAllSpecialChars() {
        #expect(MermaidHTMLBuilder.htmlEscape("<a & b>") == "&lt;a &amp; b&gt;")
    }

    @Test("htmlEscape escapes & before < and > to avoid double-escaping")
    func htmlEscapeOrderPreventDoubleEscape() {
        // If < were escaped first to &lt;, the & in &lt; could be re-escaped to &amp;lt;
        #expect(MermaidHTMLBuilder.htmlEscape("<") == "&lt;")
        #expect(MermaidHTMLBuilder.htmlEscape(">") == "&gt;")
    }

    @Test("htmlEscape handles empty string")
    func htmlEscapeEmpty() {
        #expect(MermaidHTMLBuilder.htmlEscape("") == "")
    }

    @Test("htmlEscape handles multiple consecutive special chars")
    func htmlEscapeConsecutive() {
        #expect(MermaidHTMLBuilder.htmlEscape("<<>>&&") == "&lt;&lt;&gt;&gt;&amp;&amp;")
    }

    // MARK: mermaidHTML

    @Test("mermaidHTML contains the escaped diagram text")
    func mermaidHTMLContainsDiagramText() {
        let html = MermaidHTMLBuilder.mermaidHTML("A -> B")
        #expect(html.contains("A -&gt; B"))
    }

    @Test("mermaidHTML contains mermaid div")
    func mermaidHTMLContainsMermaidDiv() {
        let html = MermaidHTMLBuilder.mermaidHTML("graph TD")
        #expect(html.contains("<div class=\"mermaid\">"))
    }

    @Test("mermaidHTML contains mermaid CDN script tag")
    func mermaidHTMLContainsScriptTag() {
        let html = MermaidHTMLBuilder.mermaidHTML("graph TD")
        #expect(html.contains("mermaid.min.js"))
    }

    @Test("mermaidHTML escapes XSS injection attempt")
    func mermaidHTMLEscapesInjection() {
        let html = MermaidHTMLBuilder.mermaidHTML("</div><script>evil()</script>")
        #expect(!html.contains("<script>evil()"))
        #expect(html.contains("&lt;/div&gt;&lt;script&gt;evil()&lt;/script&gt;"))
    }
}
