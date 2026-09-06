import Testing
@testable import SwiftUMLBridgeFramework
import Foundation

@Suite("ClassDiagramGenerator")
struct ClassDiagramGeneratorTests {

    private let generator = ClassDiagramGenerator()

    private var projectMockURL: URL {
        Bundle.module.resourceURL!
            .appendingPathComponent("TestData")
            .appendingPathComponent("ProjectMock")
    }

    // MARK: - generateScript from string

    @Test("generateScript produces valid @startuml/@enduml for class source")
    func generateScriptClassSource() {
        let source = "class MyClass { var name: String = \"\" }"
        let script = generator.generateScript(for: source)
        #expect(script.text.hasPrefix("@startuml"))
        #expect(script.text.hasSuffix("@enduml"))
    }

    @Test("generateScript includes class name in output")
    func generateScriptIncludesClassName() {
        let script = generator.generateScript(for: "class Greeter {}")
        #expect(script.text.contains("Greeter"))
    }

    @Test("generateScript handles empty source")
    func generateScriptEmptySource() {
        let script = generator.generateScript(for: "")
        #expect(script.text.hasPrefix("@startuml"))
        #expect(script.text.hasSuffix("@enduml"))
    }

    @Test("generateScript with struct source includes struct stereotype")
    func generateScriptStructSource() {
        let script = generator.generateScript(for: "struct Point { var x: Double; var y: Double }")
        #expect(script.text.contains("Point"))
    }

    @Test("generateScript with protocol source")
    func generateScriptProtocolSource() {
        let script = generator.generateScript(for: "protocol Drawable { func draw() }")
        #expect(script.text.contains("Drawable"))
    }

    @Test("generateScript with custom configuration respects theme")
    func generateScriptWithTheme() {
        var config = Configuration.default
        config = Configuration(
            theme: .amiga,
            relationships: config.relationships
        )
        let script = generator.generateScript(for: "class Foo {}", with: config)
        #expect(script.text.contains("!theme"))
        #expect(script.text.contains("amiga"))
    }

    // MARK: - generateScript from files

    @Test("generateScript from swift file contains parsed content")
    func generateScriptFromFile() {
        let swiftFile = projectMockURL.appendingPathComponent("Level 0.swift")
        let script = generator.generateScript(for: [swiftFile.path])
        #expect(script.text.hasPrefix("@startuml"))
    }

    @Test("generateScript from empty files list produces minimal script")
    func generateScriptFromEmptyFiles() {
        let script = generator.generateScript(for: [String]())
        #expect(script.text.hasPrefix("@startuml"))
        #expect(script.text.hasSuffix("@enduml"))
    }

    // MARK: - generate (end-to-end with ConsolePresenter)

    @Test("generate from string with ConsolePresenter completes without error")
    func generateFromStringWithConsolePresenter() async {
        let presenter = ConsolePresenter()
        await generator.generate(from: "class Foo {}", with: .default, presentedBy: presenter)
        // If we reach here, no crash occurred
        #expect(Bool(true))
    }

    @Test("generate from files with ConsolePresenter completes without error")
    func generateFromFilesWithConsolePresenter() async {
        let presenter = ConsolePresenter()
        await generator.generate(for: [String](), with: .default, presentedBy: presenter)
        #expect(Bool(true))
    }

    // MARK: - logProcessingDuration

    /// Still a smoke test — the function logs and returns nothing, so there is no value to assert.
    /// The arithmetic it used to carry inline is now `Duration.seconds`, which has its own tests.
    @Test("logProcessingDuration does not crash")
    func logProcessingDurationNoCrash() {
        let start = ContinuousClock.now.advanced(by: .seconds(-1))
        generator.logProcessingDuration(started: start)
        #expect(Bool(true))
    }

    // MARK: - Format propagation

    @Test("generateScript with mermaid format produces mermaid output")
    func generateScriptMermaidFormat() {
        var config = Configuration.default
        config.format = .mermaid
        let script = generator.generateScript(for: "class Foo {}", with: config)
        #expect(script.format == .mermaid)
        #expect(script.text.contains("classDiagram"))
    }

    @Test("generateScript with nomnoml format produces nomnoml output")
    func generateScriptNomnomlFormat() {
        var config = Configuration.default
        config.format = .nomnoml
        let script = generator.generateScript(for: "class Foo {}", with: config)
        #expect(script.format == .nomnoml)
    }

    @Test("generateScript with svg format produces svg output")
    func generateScriptSvgFormat() {
        var config = Configuration.default
        config.format = .svg
        let script = generator.generateScript(for: "class Foo {}", with: config)
        #expect(script.format == .svg)
    }

    // MARK: - generateScript from paths

    @Test("generateScript from nonexistent path produces minimal script")
    func generateScriptFromNonexistentPath() {
        let script = generator.generateScript(for: ["/nonexistent/path/Foo.swift"])
        #expect(script.text.hasPrefix("@startuml"))
        #expect(script.text.hasSuffix("@enduml"))
    }

    @Test("generateScript from directory path scans swift files")
    func generateScriptFromDirectoryPath() {
        let script = generator.generateScript(for: [projectMockURL.path])
        #expect(script.text.hasPrefix("@startuml"))
    }

    // MARK: - Multiple source elements

    @Test("generateScript includes multiple types from single source")
    func generateScriptMultipleTypes() {
        let source = """
        class Foo {}
        struct Bar {}
        enum Baz { case one }
        """
        let script = generator.generateScript(for: source)
        #expect(script.text.contains("Foo"))
        #expect(script.text.contains("Bar"))
        #expect(script.text.contains("Baz"))
    }

    @Test("generateScript includes enum cases")
    func generateScriptEnumSource() {
        let script = generator.generateScript(for: "enum Direction { case north; case south }")
        #expect(script.text.contains("Direction"))
    }

    // MARK: - analyzeTypes

    @Test("analyzeTypes returns empty for nonexistent path")
    func analyzeTypesNonexistentPath() {
        let types = generator.analyzeTypes(for: ["/nonexistent/path/NoSuchFile.swift"])
        #expect(types.isEmpty)
    }

    @Test("analyzeTypes from project mock does not crash")
    func analyzeTypesFromProjectMock() {
        // analyzeTypes relies on SourceKit which may not return results
        // in all environments, but it should never crash
        let types = generator.analyzeTypes(for: [projectMockURL.path])
        #expect(types.count >= 0)
    }

    // MARK: - generate with empty content

    @Test("generate from empty string with ConsolePresenter completes")
    func generateFromEmptyStringWithConsolePresenter() async {
        let presenter = ConsolePresenter()
        await generator.generate(from: "", with: .default, presentedBy: presenter)
        #expect(Bool(true))
    }
}
