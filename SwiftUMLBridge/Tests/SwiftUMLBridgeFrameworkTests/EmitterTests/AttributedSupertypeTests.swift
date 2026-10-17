import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// An attribute or specifier in an inheritance clause says how a type conforms (`@MainActor P`,
/// `@unchecked Sendable`, `nonisolated P`), not what it conforms to. These check that every diagram
/// draws the edge to `P` or `Sendable` itself, as it does without the attribute, and that excludes
/// written for the plain name hide it (#152).
@Suite("An attributed supertype is the type it names")
struct AttributedSupertypeTests {

    static let textFormats: [DiagramFormat] = [.plantuml, .mermaid, .nomnoml]

    /// Each pair: a declaration with an attributed supertype, and the same declaration without
    /// the attribute. Each source typechecks with Swift 6.4, in Swift 5 and Swift 6 mode.
    static let pairs: [(attributed: String, plain: String)] = [
        ("protocol P {}\n@MainActor final class Foo: @MainActor P {}",
         "protocol P {}\n@MainActor final class Foo: P {}"),
        ("protocol P {}\n@MainActor final class Foo {}\nextension Foo: @MainActor P {}",
         "protocol P {}\n@MainActor final class Foo {}\nextension Foo: P {}"),
        ("@globalActor actor Worker { static let shared = Worker() }\n"
            + "protocol P {}\n@Worker final class Foo: @Worker P {}",
         "@globalActor actor Worker { static let shared = Worker() }\n"
            + "protocol P {}\n@Worker final class Foo: P {}"),
        ("protocol P {}\n@MainActor final class Foo: @preconcurrency P {}",
         "protocol P {}\n@MainActor final class Foo: P {}"),
        ("protocol P {}\n@MainActor final class Foo: nonisolated P {}",
         "protocol P {}\n@MainActor final class Foo: P {}"),
        ("protocol P {}\nstruct Foo: @unsafe P {}",
         "protocol P {}\nstruct Foo: P {}"),
        ("protocol P {}\n@MainActor final class Foo: @preconcurrency @MainActor P {}",
         "protocol P {}\n@MainActor final class Foo: P {}"),
        ("protocol P {}\nprotocol Q {}\n@MainActor final class Foo: @MainActor P & Q {}",
         "protocol P {}\nprotocol Q {}\n@MainActor final class Foo: P & Q {}"),
        ("final class Box: @unchecked Sendable {}",
         "final class Box: Sendable {}"),
        ("final class Box: @unsafe @unchecked Sendable {}",
         "final class Box: Sendable {}"),
        ("final class Box: @unchecked /* checked by hand */ Sendable {}",
         "final class Box: Sendable {}"),
        ("extension Int: @retroactive Identifiable { public var id: Int { self } }",
         "extension Int: Identifiable { public var id: Int { self } }"),
        // `nonisolated` after an attribute is a late specifier; `(unsafe)` is the attribute's argument.
        ("protocol P {}\n@MainActor final class Foo: @unsafe nonisolated P {}",
         "protocol P {}\n@MainActor final class Foo: P {}"),
        ("protocol P {}\n@MainActor final class Foo: @MainActor(unsafe) P {}",
         "protocol P {}\n@MainActor final class Foo: P {}")
    ]

    /// In Swift 6 mode only, a space ends a custom attribute, so `@MainActor (P)` applies it to `(P)`.
    /// swift-syntax reads `(P)` as the attribute's argument; each is drawn as `(P)` without it is.
    static let spacedAttributePairs: [(attributed: String, plain: String)] = [
        ("protocol P {}\n@MainActor final class Foo: @MainActor (P) {}",
         "protocol P {}\n@MainActor final class Foo: (P) {}"),
        ("protocol P {}\nprotocol Q {}\n@MainActor final class Foo: @MainActor (P & Q) {}",
         "protocol P {}\nprotocol Q {}\n@MainActor final class Foo: (P & Q) {}"),
        ("protocol P {}\nprotocol Q {}\n@MainActor final class Foo: @MainActor (P) & Q {}",
         "protocol P {}\nprotocol Q {}\n@MainActor final class Foo: (P) & Q {}"),
        ("protocol P {}\nprotocol Q {}\n@MainActor final class Foo: @MainActor (P), Q {}",
         "protocol P {}\nprotocol Q {}\n@MainActor final class Foo: (P), Q {}"),
        ("@globalActor actor Worker { static let shared = Worker() }\n"
            + "protocol P {}\n@Worker final class Foo: @Worker (P) {}",
         "@globalActor actor Worker { static let shared = Worker() }\n"
            + "protocol P {}\n@Worker final class Foo: (P) {}")
    ]

    /// An isolated conformance to a protocol the file declares, and a checked-by-hand `Sendable`.
    static let isolatedAndUnchecked = """
        protocol P {}
        @MainActor final class Foo: @MainActor P {}
        final class Box: @unchecked Sendable {}
        """

    private static func configuration(
        _ format: DiagramFormat,
        _ mode: ExtensionVisualization = .all,
        relationships: RelationshipOptions = RelationshipOptions()
    ) -> Configuration {
        Configuration(elements: ElementOptions(showExtensions: mode), relationships: relationships, format: format)
    }

    private static func script(
        _ source: String,
        _ format: DiagramFormat,
        _ mode: ExtensionVisualization = .all,
        relationships: RelationshipOptions = RelationshipOptions()
    ) -> String {
        ClassDiagramGenerator().generateScript(
            for: source, with: configuration(format, mode, relationships: relationships)
        ).text
    }

    /// Each SVG edge as `"<source id> -> <target id> <style>"`.
    private static func svgEdges(
        _ source: String, relationships: RelationshipOptions = RelationshipOptions()
    ) -> [String] {
        let graph = ClassDiagramGenerator()
            .generateScript(for: source, with: configuration(.svg, relationships: relationships)).layoutGraph
        return graph?.edges.map { "\($0.sourceId) -> \($0.targetId) \($0.style)" } ?? []
    }

    /// The edge lines of a text-format script: PlantUML's and Mermaid's `<parent> <arrow> <child>`
    /// lines, and Nomnoml's `[start] arrow label [end]` lines.
    private static func edges(_ script: String) -> [String] {
        let arrows = ["<|--", "<|..", "<..", "+--"]
        return script.split(separator: "\n").map(String.init).filter { line in
            arrows.contains { line.contains(" \($0) ") } || (line.hasPrefix("[") && !line.hasPrefix("[<"))
        }
    }

    /// Writes `source` to a file of its own and hands its path to `body`.
    private static func withFile<T>(_ source: String, _ body: (String) throws -> T) throws -> T {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttributedSupertypeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Source.swift")
        try source.write(to: url, atomically: true, encoding: .utf8)
        return try body(url.path)
    }

    // MARK: - Class diagrams

    @Test("the attribute does not change the class diagram", arguments: textFormats)
    func classDiagramUnchanged(format: DiagramFormat) {
        for (attributed, plain) in Self.pairs {
            #expect(Self.script(attributed, format) == Self.script(plain, format), "\(attributed)")
        }
    }

    @Test("the edge ends on the declared protocol, with the realization arrow")
    func endsOnDeclaredProtocol() {
        let source = """
            protocol P {}
            protocol Q {}
            @MainActor final class Foo: @MainActor Q {}
            extension Foo: @MainActor P {}
            """
        #expect(Self.edges(Self.script(source, .plantuml)) == [
            "Q <|.. Foo : conforms to", "P <|.. Foo0 : conforms to", "Foo <.. Foo0 : ext"
        ])
        #expect(Self.edges(Self.script(source, .nomnoml)) == [
            "[Foo] --:> conforms to [Q]", "[Foo0] --:> conforms to [P]", "[Foo0] --> ext [Foo]"
        ])
        #expect(Self.edges(Self.script(source, .plantuml, .merged)) == [
            "Q <|.. Foo : conforms to", "P <|.. Foo : conforms to"
        ])
    }

    @Test("SVG draws the edge to the declared protocol")
    func svgEndsOnDeclaredProtocol() {
        for (attributed, plain) in Self.pairs {
            #expect(Self.svgEdges(attributed) == Self.svgEdges(plain), "\(attributed)")
        }
        #expect(!Self.svgEdges(Self.pairs[0].attributed).isEmpty)
    }

    @Test("an exclude written for the plain name hides the attributed edge", arguments: textFormats)
    func excludeMatchesPlainName(format: DiagramFormat) {
        let patterns = ["Sendable", "P"]
        let realize = RelationshipOptions(realize: Relationship(label: "conforms to", exclude: patterns))
        let inheritance = RelationshipOptions(inheritance: Relationship(label: "inherits", exclude: patterns))
        let source = Self.isolatedAndUnchecked
        #expect(Self.edges(Self.script(source, format, relationships: realize)).isEmpty)
        #expect(Self.edges(Self.script(source, format, relationships: inheritance)).isEmpty)
    }

    @Test("SVG: an exclude written for the plain name hides the attributed edge")
    func svgExcludeMatchesPlainName() {
        let realize = RelationshipOptions(realize: Relationship(label: "conforms to", exclude: ["P"]))
        #expect(Self.svgEdges(Self.isolatedAndUnchecked) == ["Foo -> P inheritance"])
        #expect(Self.svgEdges(Self.isolatedAndUnchecked, relationships: realize).isEmpty)
    }

    @Test("an attribute a space ends applies to the type after it", arguments: textFormats + [.svg])
    func spacedAttribute(format: DiagramFormat) {
        for (attributed, plain) in Self.spacedAttributePairs {
            let script = ClassDiagramGenerator().generateScript(for: attributed, with: Self.configuration(format))
            let control = ClassDiagramGenerator().generateScript(for: plain, with: Self.configuration(format))
            #expect(script.text == control.text, "\(attributed)")
            #expect(script.layoutGraph?.edges.map(\.targetId) == control.layoutGraph?.edges.map(\.targetId))
        }
    }

    /// An unfinished clause has no type to draw an edge to.
    @Test("an entry with no type draws no edge")
    func entryWithNoType() {
        #expect(Self.edges(Self.script("class Foo: {}", .plantuml)).isEmpty)
        #expect(Self.edges(Self.script("final class Box: @unchecked {}", .plantuml)).isEmpty)
    }

    /// A conformance written with `@retroactive` for new compilers and without it for old ones is
    /// one conformance: merged, the #76 de-duplication draws it once.
    @Test("a conformance two #if clauses write with and without @retroactive is drawn once, merged")
    func retroactiveInBothClausesMerged() {
        let source = """
            #if hasFeature(RetroactiveAttribute)
            extension Int: @retroactive Identifiable { public var id: Int { self } }
            #else
            extension Int: Identifiable { public var id: Int { self } }
            #endif
            """
        #expect(Self.edges(Self.script(source, .plantuml, .merged)) == ["Identifiable <.. Int : inherits"])
        #expect(Self.edges(Self.script(source, .plantuml)) == [
            "Identifiable <.. Int : inherits", "Identifiable <.. Int0 : inherits"
        ])
    }

    /// `~Copyable` suppresses a conformance; it is not an attributed one, and is left as written.
    @Test("a suppressed conformance keeps its name")
    func suppressedConformanceUnchanged() {
        #expect(Self.edges(Self.script("struct Token: ~Copyable {}", .plantuml)) == ["~Copyable <|-- Token : inherits"])
    }

    // MARK: - deps, ER and TypeInfo

    @Test("deps --types draws the edge to the type the attribute is on")
    func depsEdges() throws {
        let source = """
            protocol P {}
            protocol Q {}
            @MainActor final class Foo: @MainActor Q {}
            extension Foo: @MainActor P {}
            final class Box: @unchecked Sendable {}
            """
        let edges = try Self.withFile(source) { DependencyGraphGenerator().extractEdges(for: [$0], mode: .types) }
        #expect(edges.map { "\($0.from) -> \($0.to)" } == ["Foo -> Q", "Foo -> P", "Box -> Sendable"])
        let excluding = Configuration(elements: ElementOptions(exclude: ["Sendable"]))
        let kept = try Self.withFile(source) {
            DependencyGraphGenerator().extractEdges(for: [$0], mode: .types, with: excluding)
        }
        #expect(kept.map { "\($0.from) -> \($0.to)" } == ["Foo -> Q", "Foo -> P"])
    }

    /// A type in a target that defaults to `@MainActor` keeps a GRDB conformance nonisolated.
    @Test("a GRDB record whose conformance is attributed is an ER entity")
    func grdbRecord() {
        let source = """
            protocol FetchableRecord {}
            protocol PersistableRecord {}
            struct Player: Codable, FetchableRecord, PersistableRecord {
                var id: Int64
                var name: String
            }
            @MainActor struct Team: Codable, nonisolated FetchableRecord, nonisolated PersistableRecord {
                var id: Int64
                var title: String
            }
            """
        #expect(PersistenceSchemaExtractor.extract(from: source).entities.map(\.name) == ["Player", "Team"])
    }

    @Test("TypeInfo names the inherited type without its attribute")
    func typeInfoNames() throws {
        let types = try Self.withFile(Self.isolatedAndUnchecked) { ClassDiagramGenerator().analyzeTypes(for: [$0]) }
        #expect(types.map(\.inheritedTypeNames) == [[], ["P"], ["Sendable"]])
    }
}
