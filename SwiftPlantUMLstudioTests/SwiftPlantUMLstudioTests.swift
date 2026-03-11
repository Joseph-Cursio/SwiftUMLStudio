//
//  SwiftPlantUMLstudioTests.swift
//  SwiftPlantUMLstudioTests
//
//  Created by joe cursio on 2/26/26.
//

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
    // SequenceDiagramGenerator uses SourceKitten under the hood, so running it inside
    // the Xcode app test host causes the XPC connection to sourcekitd to hang
    // indefinitely (no crash — just a frozen await). Accumulated hung Task.detached
    // instances eventually freeze the whole test process.
    //
    // These tests are covered by SequenceDiagramGeneratorTests in the
    // SwiftUMLBridgeFramework package test suite (run via `swift test`).

    @Test("generateSequenceDiagram produces a script with the entry point in the title",
          .disabled("sourcekitd hangs in the Xcode test host — run via `swift test` instead"))
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

    @Test("generateSequenceDiagram produces a Mermaid script with the entry point",
          .disabled("sourcekitd hangs in the Xcode test host — run via `swift test` instead"))
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
    // DependencyGraphGenerator calls SourceKitten regardless of mode; the Xcode app
    // test host cannot connect to sourcekitd without the toolchain environment, so the
    // XPC call hangs. Covered by DependencyGraphGeneratorTests in the framework suite.

    @Test("generateDependencyGraph (modules) produces a script containing imported module names",
          .disabled("sourcekitd hangs in the Xcode test host — run via `swift test` instead"))
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
