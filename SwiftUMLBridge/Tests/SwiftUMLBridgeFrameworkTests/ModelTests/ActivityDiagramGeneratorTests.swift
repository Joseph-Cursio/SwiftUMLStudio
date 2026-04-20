import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

@Suite("ActivityDiagramGenerator")
struct ActivityDiagramGeneratorTests {

    private let generator = ActivityDiagramGenerator()

    private func tempSwiftFile(_ source: String) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("swift")
        try source.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    // MARK: - Entry points

    @Test("findEntryPoints returns Type.method strings sorted")
    func findEntryPointsSorted() throws {
        let source = """
        class Zebra { func zap() {} }
        class Alpha {
            func act() {}
            func begin() {}
        }
        """
        let path = try tempSwiftFile(source)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let entries = generator.findEntryPoints(for: [path])
        #expect(entries == entries.sorted())
        #expect(entries.contains("Alpha.act"))
        #expect(entries.contains("Alpha.begin"))
        #expect(entries.contains("Zebra.zap"))
    }

    @Test("findEntryPoints on nonexistent path returns empty")
    func findEntryPointsNonexistent() {
        #expect(generator.findEntryPoints(for: ["/nonexistent/Foo.swift"]).isEmpty)
    }

    // MARK: - Script generation

    @Test("entry found in source produces non-empty PlantUML script")
    func scriptForValidEntry() throws {
        let source = """
        class Foo {
            func run() {
                if flag {
                    hit()
                } else {
                    miss()
                }
            }
        }
        """
        let path = try tempSwiftFile(source)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let script = generator.generateScript(
            for: [path], entryType: "Foo", entryMethod: "run"
        )
        #expect(!script.text.isEmpty)
        #expect(script.text.contains("title Foo.run"))
        #expect(script.text.contains("<<choice>>"))
    }

    @Test("missing entry produces an empty PlantUML shell")
    func scriptForMissingEntry() throws {
        let source = "class Foo { func run() {} }"
        let path = try tempSwiftFile(source)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let script = generator.generateScript(
            for: [path], entryType: "Nope", entryMethod: "run"
        )
        #expect(script.text.contains("@startuml"))
        #expect(script.text.contains("@enduml"))
        #expect(script.text.contains("<<choice>>") == false)
    }

    @Test("Mermaid format produces flowchart output")
    func mermaidFormat() throws {
        let source = "class Foo { func run() { doThing() } }"
        let path = try tempSwiftFile(source)
        defer { try? FileManager.default.removeItem(atPath: path) }

        var config = Configuration.default
        config.format = .mermaid
        let script = generator.generateScript(
            for: [path], entryType: "Foo", entryMethod: "run", with: config
        )
        #expect(script.text.hasPrefix("flowchart TD"))
    }

    @Test("SVG format populates activityLayout")
    func svgFormatPopulatesLayout() throws {
        let source = "class Foo { func run() { doThing() } }"
        let path = try tempSwiftFile(source)
        defer { try? FileManager.default.removeItem(atPath: path) }

        var config = Configuration.default
        config.format = .svg
        let script = generator.generateScript(
            for: [path], entryType: "Foo", entryMethod: "run", with: config
        )
        #expect(script.activityLayout != nil)
        #expect(script.activityLayout?.title == "Foo.run")
    }

    @Test("empty paths yield an empty-shell script")
    func emptyPathsEmptyShell() {
        let script = generator.generateScript(
            for: [], entryType: "Foo", entryMethod: "run"
        )
        #expect(script.text.contains("@startuml"))
        #expect(script.text.contains("@enduml"))
    }
}
