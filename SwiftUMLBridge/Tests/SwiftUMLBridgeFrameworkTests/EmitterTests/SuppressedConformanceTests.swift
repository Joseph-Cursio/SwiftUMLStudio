import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// `~Copyable` or `~Escapable` in an inheritance clause says a type does not conform to
/// `Copyable` or `Escapable`. These check that no diagram draws it as a supertype, in any format
/// or extension mode, in `deps` or in `TypeInfo`, and that what the clause does name is kept.
@Suite("A suppressed conformance is not a supertype")
struct SuppressedConformanceTests {

    static let formats: [DiagramFormat] = [.plantuml, .mermaid, .nomnoml, .svg]
    static let modes: [ExtensionVisualization] = [.all, .merged, .none]

    static let source = """
        protocol Resource: ~Copyable {}
        struct Token: Resource, ~Copyable, Sendable {}
        struct Box<Value: ~Copyable>: ~Copyable {}
        extension Box: Copyable where Value: Copyable {}
        enum Flag: ~Copyable & ~Escapable { case set }
        struct Odd: @unchecked ~Copyable {}
        """

    private static func script(_ format: DiagramFormat, _ mode: ExtensionVisualization) -> String {
        let configuration = Configuration(elements: ElementOptions(showExtensions: mode), format: format)
        return ClassDiagramGenerator().generateScript(for: source, with: configuration).text
    }

    /// Writes `source` to a file of its own and hands its path to `body`.
    private static func withFile<T>(_ body: (String) throws -> T) throws -> T {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SuppressedConformanceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Source.swift")
        try source.write(to: url, atomically: true, encoding: .utf8)
        return try body(url.path)
    }

    @Test("no class diagram names a suppressed protocol, except in a generic header")
    func classDiagrams() {
        var found: [String] = []
        for format in Self.formats {
            for mode in Self.modes {
                found += Self.script(format, mode).split(separator: "\n")
                    .filter { $0.contains("~Copyable") || $0.contains("~Escapable") }
                    .filter { !$0.contains("Value: ~Copyable") }
                    .map { "\(format) \(mode): \($0.trimmingCharacters(in: .whitespaces))" }
            }
        }
        #expect(found == [])
    }

    @Test("deps --types draws no edge to a suppressed protocol")
    func depsEdges() throws {
        let edges = try Self.withFile { DependencyGraphGenerator().extractEdges(for: [$0], mode: .types) }
        #expect(edges.map { "\($0.from) -> \($0.to)" } == ["Token -> Resource", "Token -> Sendable", "Box -> Copyable"])
    }

    @Test("TypeInfo lists no suppressed protocol")
    func typeInfoNames() throws {
        let types = try Self.withFile { ClassDiagramGenerator().analyzeTypes(for: [$0]) }
        #expect(types.map(\.inheritedTypeNames) == [[], ["Resource", "Sendable"], [], ["Copyable"], [], []])
    }

    /// Each spelling the parser unwraps before it reads a name: parentheses (#160), a composition
    /// split across lines, and an attribute in front of the parentheses, which Swift 6 reads.
    @Test("an unwrapped suppressed entry is dropped too", arguments: [
        "struct Par: (~Copyable) {}",
        "struct Par: P & (~Copyable) {}",
        "struct Par: P &\n    ~Copyable {}",
        "struct Par: @MainActor (~Copyable) {}",
        "struct Par: P, ~Swift.Copyable {}"
    ])
    func unwrapped(declaration: String) {
        let configuration = Configuration(format: .plantuml)
        let text = ClassDiagramGenerator()
            .generateScript(for: "protocol P: ~Copyable {}\n" + declaration, with: configuration).text
        #expect(text.split(separator: "\n").filter { $0.contains("~") } == [])
    }

    // MARK: - Guards: these pass today, and a fix should keep them passing.

    /// A raw identifier keeps its backticks, so a protocol named `` `~Foo` `` is still a supertype.
    @Test("a protocol whose raw name starts with a tilde is still drawn")
    func rawIdentifier() {
        let source = "protocol `~Foo` {}\nstruct S: `~Foo` {}"
        let text = ClassDiagramGenerator().generateScript(for: source, with: Configuration(format: .plantuml)).text
        #expect(text.split(separator: "\n").contains("`~Foo` <|.. S : conforms to"))
    }

    @Test("a generic header still shows its constraint", arguments: [DiagramFormat.plantuml, .mermaid, .nomnoml])
    func genericHeader(format: DiagramFormat) {
        #expect(Self.script(format, .all).contains("Value: ~Copyable"))
    }

    @Test("a conditional Copyable conformance is still drawn")
    func conditionalCopyable() {
        let lines = { (mode: ExtensionVisualization) in Self.script(.plantuml, mode).split(separator: "\n") }
        #expect(lines(.merged).contains("Copyable <|-- Box : inherits"))
        #expect(lines(.all).contains("Copyable <.. Box0 : inherits"))
    }
}
