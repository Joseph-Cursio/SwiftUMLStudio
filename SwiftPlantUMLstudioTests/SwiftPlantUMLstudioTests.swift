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

// MARK: - DiagramMode Tests

@Suite("DiagramMode")
struct DiagramModeTests {

    @Test("has exactly three cases")
    func allCasesCount() {
        #expect(DiagramMode.allCases.count == 3)
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
    @MainActor
    func idEqualsRawValue() {
        for mode in DiagramMode.allCases {
            #expect(mode.id == mode.rawValue)
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
    @MainActor
    func defaultDiagramMode() {
        let vm = DiagramViewModel()
        #expect(vm.diagramMode == .classDiagram)
    }

    @Test("default diagramFormat is plantuml")
    @MainActor
    func defaultDiagramFormat() {
        let vm = DiagramViewModel()
        #expect(vm.diagramFormat == .plantuml)
    }

    @Test("default depsMode is types")
    @MainActor
    func defaultDepsMode() {
        let vm = DiagramViewModel()
        #expect(vm.depsMode == .types)
    }

    @Test("default sequenceDepth is 3")
    @MainActor
    func defaultSequenceDepth() {
        let vm = DiagramViewModel()
        #expect(vm.sequenceDepth == 3)
    }

    @Test("default entryPoint is empty string")
    @MainActor
    func defaultEntryPoint() {
        let vm = DiagramViewModel()
        #expect(vm.entryPoint == "")
    }

    @Test("default selectedPaths is empty")
    @MainActor
    func defaultSelectedPaths() {
        let vm = DiagramViewModel()
        #expect(vm.selectedPaths.isEmpty)
    }

    @Test("default isGenerating is false")
    @MainActor
    func defaultIsGenerating() {
        let vm = DiagramViewModel()
        #expect(vm.isGenerating == false)
    }

    @Test("default errorMessage is nil")
    @MainActor
    func defaultErrorMessage() {
        let vm = DiagramViewModel()
        #expect(vm.errorMessage == nil)
    }

    // MARK: currentScript

    @Test("currentScript is nil initially for classDiagram mode")
    @MainActor
    func currentScriptNilForClassDiagram() {
        let vm = DiagramViewModel()
        vm.diagramMode = .classDiagram
        #expect(vm.currentScript == nil)
    }

    @Test("currentScript is nil initially for sequenceDiagram mode")
    @MainActor
    func currentScriptNilForSequenceDiagram() {
        let vm = DiagramViewModel()
        vm.diagramMode = .sequenceDiagram
        #expect(vm.currentScript == nil)
    }

    @Test("currentScript is nil initially for dependencyGraph mode")
    @MainActor
    func currentScriptNilForDependencyGraph() {
        let vm = DiagramViewModel()
        vm.diagramMode = .dependencyGraph
        #expect(vm.currentScript == nil)
    }

    // MARK: generate() guard logic
    //
    // generate() always sets isGenerating = true synchronously, then an async task runs the
    // per-mode guard and sets it back to false. Tests must be async and await Task.yield() so
    // the spawned task can complete its guard branch before the assertion runs.

    @Test("generate resets isGenerating when selectedPaths is empty for classDiagram")
    @MainActor
    func generateGuardsEmptyPathsClassDiagram() async {
        let vm = DiagramViewModel()
        vm.diagramMode = .classDiagram
        vm.selectedPaths = []

        vm.generate()
        await Task.yield()

        #expect(vm.isGenerating == false)
    }

    @Test("generate resets isGenerating when selectedPaths is empty for dependencyGraph")
    @MainActor
    func generateGuardsEmptyPathsDependencyGraph() async {
        let vm = DiagramViewModel()
        vm.diagramMode = .dependencyGraph
        vm.selectedPaths = []

        vm.generate()
        await Task.yield()

        #expect(vm.isGenerating == false)
    }

    @Test("generate resets isGenerating when selectedPaths is empty for sequenceDiagram")
    @MainActor
    func generateGuardsEmptyPathsSequenceDiagram() async {
        let vm = DiagramViewModel()
        vm.diagramMode = .sequenceDiagram
        vm.selectedPaths = []
        vm.entryPoint = "Foo.bar"

        vm.generate()
        await Task.yield()

        #expect(vm.isGenerating == false)
    }

    @Test("generate resets isGenerating for sequenceDiagram with empty entryPoint")
    @MainActor
    func generateGuardsEmptyEntryPoint() async {
        let vm = DiagramViewModel()
        vm.diagramMode = .sequenceDiagram
        vm.selectedPaths = ["/some/path.swift"]
        vm.entryPoint = ""

        vm.generate()
        await Task.yield()

        #expect(vm.isGenerating == false)
    }

    @Test("generate resets isGenerating for sequenceDiagram with malformed entryPoint (no dot)")
    @MainActor
    func generateGuardsMalformedEntryPointNoDot() async {
        let vm = DiagramViewModel()
        vm.diagramMode = .sequenceDiagram
        vm.selectedPaths = ["/some/path.swift"]
        vm.entryPoint = "FooBar"

        vm.generate()
        await Task.yield()

        #expect(vm.isGenerating == false)
    }

    @Test("generate resets isGenerating for sequenceDiagram with too many dots in entryPoint")
    @MainActor
    func generateGuardsMalformedEntryPointTooManyDots() async {
        let vm = DiagramViewModel()
        vm.diagramMode = .sequenceDiagram
        vm.selectedPaths = ["/some/path.swift"]
        vm.entryPoint = "Foo.bar.baz"

        vm.generate()
        await Task.yield()

        #expect(vm.isGenerating == false)
    }
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

        let vm = DiagramViewModel()
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

        let vm = DiagramViewModel()
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
    // DependencyGraphGenerator in .types mode calls SyntaxStructure.create(from:) and
    // crashes for the same sourcekitd reason described in the Class Diagram section above.
    // Type-dependency extraction is covered by DependencyGraphGeneratorTests in the
    // framework test suite.

    @Test("generateDependencyGraph (modules) produces a script containing imported module names")
    @MainActor
    func generateDependencyGraphModules() async throws {
        let dir = try makeFixtureDir(writing: """
            import Foundation
            import Combine
            struct MyModel {}
            """)
        defer { try? FileManager.default.removeItem(at: dir) }

        let vm = DiagramViewModel()
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
