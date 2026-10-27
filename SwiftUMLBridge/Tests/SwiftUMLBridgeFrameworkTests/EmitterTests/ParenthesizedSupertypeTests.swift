import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// Swift reads `struct Foo: (P)` as `struct Foo: P`, and `(P & Q)` and `(P) & Q` as `P & Q`. Every
/// reader should too.
@Suite("A parenthesized supertype is the type inside the parentheses")
struct ParenthesizedSupertypeTests {

    static let textFormats: [DiagramFormat] = [.plantuml, .mermaid, .nomnoml]

    /// Each pair: a clause with parentheses, and the same clause without them. Each source
    /// typechecks with Swift 6.4 in Swift 5 and Swift 6 mode, but the last: Swift 6 mode only.
    static let pairs: [(parenthesized: String, plain: String)] = [
        ("protocol P {}\nstruct Foo: (P) {}", "protocol P {}\nstruct Foo: P {}"),
        ("protocol P {}\nstruct Foo: ((P)) {}", "protocol P {}\nstruct Foo: P {}"),
        ("protocol P {}\nstruct Foo: (P,) {}", "protocol P {}\nstruct Foo: P {}"),
        ("protocol P {}\nprotocol Q {}\nstruct Foo: (P & Q) {}", "protocol P {}\nprotocol Q {}\nstruct Foo: P & Q {}"),
        ("protocol P {}\nprotocol Q {}\nstruct Foo: (P) & Q {}", "protocol P {}\nprotocol Q {}\nstruct Foo: P & Q {}"),
        ("protocol P {}\nprotocol Q {}\nprotocol R {}\nstruct Foo: (P & Q) & R {}",
         "protocol P {}\nprotocol Q {}\nprotocol R {}\nstruct Foo: P & Q & R {}"),
        ("protocol P {}\nprotocol Q {}\nstruct Foo: (P), Q {}", "protocol P {}\nprotocol Q {}\nstruct Foo: P, Q {}"),
        ("protocol P {}\n@MainActor final class Foo: (@MainActor P) {}",
         "protocol P {}\n@MainActor final class Foo: P {}"),
        ("final class Box: (@unchecked Sendable) {}", "final class Box: Sendable {}"),
        ("final class Box: @unchecked (Sendable) {}", "final class Box: Sendable {}"),
        ("class Base {}\nfinal class Sub: (Base) {}", "class Base {}\nfinal class Sub: Base {}"),
        ("protocol P {}\nstruct Foo {}\nextension Foo: (P) {}", "protocol P {}\nstruct Foo {}\nextension Foo: P {}"),
        ("protocol P {}\nprotocol R: (P) {}", "protocol P {}\nprotocol R: P {}"),
        ("enum Foo: (Int) { case one }", "enum Foo: Int { case one }"),
        ("struct Token: (~Copyable) {}", "struct Token: ~Copyable {}"),
        ("protocol P {}\n@MainActor final class Foo: @MainActor ((P)) {}",
         "protocol P {}\n@MainActor final class Foo: P {}")
    ]

    static let shapes = """
        protocol Shape {}
        protocol Named {}
        class Base {}
        final class Circle: Base, (Shape) {}
        struct Square: (Shape & Named) {}
        struct Label {}
        extension Label: (Named) {}
        """

    /// Each SVG edge as `"<source id> -> <target id> <style>"`.
    private static func svgEdges(_ source: String) -> [String] {
        let graph = classDiagram(source, .svg).layoutGraph
        return graph?.edges.map { "\($0.sourceId) -> \($0.targetId) \($0.style)" } ?? []
    }

    /// Writes `source` to a file of its own and hands its path to `body`.
    private static func withFile<T>(_ source: String, _ body: (String) throws -> T) throws -> T {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ParenthesizedSupertypeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Source.swift")
        try source.write(to: url, atomically: true, encoding: .utf8)
        return try body(url.path)
    }

    // MARK: - Class diagrams

    @Test("the parentheses do not change the class diagram", arguments: textFormats)
    func classDiagramUnchanged(format: DiagramFormat) {
        for (parenthesized, plain) in Self.pairs {
            #expect(classDiagram(parenthesized, format).text == classDiagram(plain, format).text, "\(parenthesized)")
        }
    }

    @Test("SVG draws the parenthesized supertype's edge as the plain one's")
    func svgUnchanged() {
        for (parenthesized, plain) in Self.pairs {
            #expect(Self.svgEdges(parenthesized) == Self.svgEdges(plain), "\(parenthesized)")
        }
    }

    @Test("each edge ends on the declared type, with the realization arrow to a protocol")
    func endsOnDeclaredTypes() {
        #expect(edgeLines(classDiagram(Self.shapes, .plantuml).text) == [
            "Base <|-- Circle : inherits",
            "Shape <|.. Circle : conforms to",
            "Shape <|.. Square : conforms to",
            "Named <|.. Square : conforms to",
            "Named <|.. Label0 : conforms to",
            "Label <.. Label0 : ext"
        ])
        #expect(Self.svgEdges(Self.shapes).count == 6)
    }

    @Test("an exclude written for the plain name hides the parenthesized edge", arguments: textFormats)
    func excludeMatchesPlainName(format: DiagramFormat) {
        let source = """
            protocol Shape {}
            protocol Named {}
            struct Square: (Shape & Named) {}
            struct Label: (Named) {}
            final class Box: (@unchecked Sendable) {}
            """
        let patterns = ["Shape", "Named", "Sendable"]
        let realize = RelationshipOptions(realize: Relationship(label: "conforms to", exclude: patterns))
        let inheritance = RelationshipOptions(inheritance: Relationship(label: "inherits", exclude: patterns))
        #expect(!edgeLines(classDiagram(source, format).text).isEmpty)
        #expect(edgeLines(classDiagram(source, format, relationships: realize).text).isEmpty)
        #expect(edgeLines(classDiagram(source, format, relationships: inheritance).text).isEmpty)
    }

    // MARK: - deps, ER and TypeInfo

    @Test("deps --types draws the edge to the type inside the parentheses")
    func depsEdges() throws {
        let edges = try Self.withFile(Self.shapes) { DependencyGraphGenerator().extractEdges(for: [$0], mode: .types) }
        #expect(edges.map { "\($0.from) -> \($0.to)" } == [
            "Circle -> Base", "Circle -> Shape", "Square -> Shape", "Square -> Named", "Label -> Named"
        ])
        let excluding = Configuration(elements: ElementOptions(exclude: ["Shape", "Named"]))
        let kept = try Self.withFile(Self.shapes) {
            DependencyGraphGenerator().extractEdges(for: [$0], mode: .types, with: excluding)
        }
        #expect(kept.map { "\($0.from) -> \($0.to)" } == ["Circle -> Base"])
    }

    @Test("a GRDB record whose conformance is parenthesized is an ER entity")
    func grdbRecord() {
        let source = """
            protocol FetchableRecord {}
            protocol PersistableRecord {}
            struct Player: Codable, FetchableRecord, PersistableRecord {
                var id: Int64
                var name: String
            }
            struct Team: Codable, (FetchableRecord), (PersistableRecord) {
                var id: Int64
                var title: String
            }
            struct Club: Codable, (FetchableRecord & PersistableRecord) {
                var id: Int64
                var city: String
            }
            """
        #expect(PersistenceSchemaExtractor.extract(from: source).entities.map(\.name) == ["Player", "Team", "Club"])
    }

    @Test("TypeInfo names the inherited type without its parentheses")
    func typeInfoNames() throws {
        let types = try Self.withFile(Self.shapes) { ClassDiagramGenerator().analyzeTypes(for: [$0]) }
        #expect(types.map(\.inheritedTypeNames) == [[], [], [], ["Base", "Shape"], ["Shape", "Named"], [], ["Named"]])
    }
}
