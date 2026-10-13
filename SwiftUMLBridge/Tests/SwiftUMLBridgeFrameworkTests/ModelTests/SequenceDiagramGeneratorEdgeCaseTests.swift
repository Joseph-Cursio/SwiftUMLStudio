import Testing
@testable import SwiftUMLBridgeFramework
import Foundation

@Suite("SequenceDiagramGenerator - Edge Cases and Format")
struct SequenceDiagramGeneratorEdgeCaseTests {

    private let generator = SequenceDiagramGenerator()

    // MARK: - Helper

    /// Writes `source` to a uniquely-named temp `.swift` file and returns its path.
    private func tempSwiftFile(_ source: String) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("swift")
        try source.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    // MARK: - Format propagation

    @Test("plantuml format produces @startuml header")
    func plantumlFormatProducesStartuml() throws {
        let source = """
        class Foo {
            func run() { self.helper() }
            func helper() {}
        }
        """
        let path = try tempSwiftFile(source)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let script = generator.generateScript(for: [path], entryType: "Foo", entryMethod: "run")
        #expect(script.format == .plantuml)
        #expect(script.text.hasPrefix("@startuml"))
    }

    @Test("mermaid format produces sequenceDiagram header")
    func mermaidFormatProducesSequenceDiagramHeader() throws {
        let source = """
        class Foo {
            func run() { self.helper() }
            func helper() {}
        }
        """
        let path = try tempSwiftFile(source)
        defer { try? FileManager.default.removeItem(atPath: path) }

        var config = Configuration.default
        config.format = .mermaid
        let script = generator.generateScript(
            for: [path], entryType: "Foo", entryMethod: "run", with: config
        )
        #expect(script.format == .mermaid)
        #expect(script.text.contains("sequenceDiagram"))
    }

    // MARK: - generateScript edge cases

    @Test("generateScript with nonexistent path produces empty-like script")
    func generateScriptNonexistentPath() {
        let script = generator.generateScript(
            for: ["/does/not/exist.swift"],
            entryType: "Foo",
            entryMethod: "run"
        )
        #expect(script.text.contains("->") == false)
    }

    @Test("generateScript with depth 0 includes no calls")
    func generateScriptDepthZero() throws {
        let source = """
        class Foo {
            func run() { self.helper() }
            func helper() {}
        }
        """
        let path = try tempSwiftFile(source)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let script = generator.generateScript(
            for: [path], entryType: "Foo", entryMethod: "run", depth: 0
        )
        #expect(script.text.contains("helper") == false)
    }

    @Test("generateScript with nomnoml format falls back to Mermaid and reports mermaid")
    func nomnomlFormatFallsBackToMermaid() throws {
        let source = """
        class Foo {
            func run() { self.helper() }
            func helper() {}
        }
        """
        let path = try tempSwiftFile(source)
        defer { try? FileManager.default.removeItem(atPath: path) }

        var config = Configuration.default
        config.format = .nomnoml
        let script = generator.generateScript(
            for: [path], entryType: "Foo", entryMethod: "run", with: config
        )
        #expect(script.format == .mermaid)
        #expect(script.text.hasPrefix("sequenceDiagram"))
    }

    @Test("generateScript with svg format propagates format")
    func svgFormatPropagation() throws {
        let source = """
        class Foo {
            func run() { self.helper() }
            func helper() {}
        }
        """
        let path = try tempSwiftFile(source)
        defer { try? FileManager.default.removeItem(atPath: path) }

        var config = Configuration.default
        config.format = .svg
        let script = generator.generateScript(
            for: [path], entryType: "Foo", entryMethod: "run", with: config
        )
        #expect(script.format == .svg)
    }

    // MARK: - Multiple files

    @Test("edges from multiple files are combined for traversal")
    func multipleFilesCombineEdgesAcrossFiles() throws {
        let source1 = """
        class ServiceA {
            func start() { ServiceB.process() }
        }
        """
        let source2 = """
        class ServiceB {
            func process() { self.finish() }
            func finish() {}
        }
        """
        let path1 = try tempSwiftFile(source1)
        let path2 = try tempSwiftFile(source2)
        defer {
            try? FileManager.default.removeItem(atPath: path1)
            try? FileManager.default.removeItem(atPath: path2)
        }

        let script = generator.generateScript(
            for: [path1, path2],
            entryType: "ServiceA",
            entryMethod: "start",
            depth: 5
        )
        #expect(script.text.contains("process"))
        #expect(script.text.contains("finish"))
    }
}
