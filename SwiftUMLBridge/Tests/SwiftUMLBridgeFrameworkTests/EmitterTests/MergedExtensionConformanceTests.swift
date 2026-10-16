import Testing
@testable import SwiftUMLBridgeFramework

/// Under `showExtensions: .merged`, the supertypes an extension's inheritance clause names are
/// drawn from the box its members are merged into, as that type's own supertypes are. Merging
/// used to fold in only the members, so `extension Foo: P {}` drew no edge at all (#76).
@Suite("Merged extensions — the conformances they declare")
struct MergedExtensionConformanceTests {

    static let textFormats: [DiagramFormat] = [.plantuml, .mermaid, .nomnoml]

    private static func script(
        _ source: String,
        _ format: DiagramFormat,
        _ mode: ExtensionVisualization = .merged,
        relationships: RelationshipOptions = RelationshipOptions()
    ) -> String {
        let configuration = Configuration(
            elements: ElementOptions(showExtensions: mode), relationships: relationships, format: format
        )
        return ClassDiagramGenerator().generateScript(for: source, with: configuration).text
    }

    /// The edge lines of a text-format script, in drawing order: PlantUML's and Mermaid's
    /// `<parent> <arrow> <child>` lines, and Nomnoml's `[start] arrow label [end]` lines.
    private static func edges(_ script: String) -> [String] {
        let arrows: Set<String> = ["<|--", "<|..", "<..", "--", "+--"]
        return script.split(separator: "\n").map(String.init).filter { line in
            let words = line.split(separator: " ")
            let isArrowLine = words.count >= 3 && arrows.contains(String(words[1]))
            return isArrowLine || (line.hasPrefix("[") && !line.hasPrefix("[<"))
        }
    }

    private static func edges(
        _ source: String,
        _ format: DiagramFormat,
        _ mode: ExtensionVisualization = .merged,
        relationships: RelationshipOptions = RelationshipOptions()
    ) -> [String] {
        edges(script(source, format, mode, relationships: relationships))
    }

    // MARK: - Drawn from the type's box

    @Test("an empty extension's conformance is drawn from the type it merges into")
    func emptyExtension() {
        let source = "protocol P {}\nstruct Foo {}\nextension Foo: P {}"
        // Control: shown, the extension draws it from its own box (#68).
        #expect(Self.edges(source, .plantuml, .all) == ["P <|.. Foo0 : conforms to", "Foo <.. Foo0 : ext"])
        #expect(Self.edges(source, .plantuml) == ["P <|.. Foo : conforms to"])
        #expect(Self.edges(source, .mermaid) == ["P <|.. Foo : conforms to"])
        #expect(Self.edges(source, .nomnoml) == ["[Foo] --:> conforms to [P]"])
    }

    @Test("a type keeps its own superclass and gains each conformance its extension adds")
    func ownSuperclassAndCarriedConformances() {
        let source = "class Base {}\nprotocol P {}\nprotocol Q {}\nclass Sub: Base {}\nextension Sub: P, Q {}"
        #expect(Self.edges(source, .plantuml) == [
            "Base <|-- Sub : inherits", "P <|.. Sub : conforms to", "Q <|.. Sub : conforms to"
        ])
        #expect(Self.edges(source, .nomnoml) == [
            "[Sub] -:> inherits [Base]", "[Sub] --:> conforms to [P]", "[Sub] --:> conforms to [Q]"
        ])
    }

    @Test("an extension with members carries its conformance too")
    func extensionWithMembers() {
        let source = "protocol P {}\nstruct Foo {}\nextension Foo: P { func bar() {} }"
        let plantUML = Self.script(source, .plantuml)
        #expect(Self.edges(plantUML) == ["P <|.. Foo : conforms to"])
        #expect(plantUML.contains("~bar <&bolt>"))
    }

    @Test("each part of a composition is drawn")
    func composition() {
        let source = "protocol P {}\nprotocol Q {}\nstruct Foo {}\nextension Foo: P & Q {}"
        #expect(Self.edges(source, .mermaid) == ["P <|.. Foo : conforms to", "Q <|.. Foo : conforms to"])
    }

    /// The parser already splits `P & Q`, so this builds a carried composition by hand, as the
    /// tests of a type's own composition do.
    @Test("a carried composition is split, as the type's own is")
    func carriedCompositionIsSplit() {
        let items = [
            SyntaxStructure(kind: .protocol, name: "P"),
            SyntaxStructure(kind: .protocol, name: "Q"),
            SyntaxStructure(kind: .struct, name: "Foo"),
            SyntaxStructure(inheritedTypes: [SyntaxStructure(name: "P & Q")], kind: .extension, name: "Foo")
        ]
        let configuration = Configuration(elements: ElementOptions(showExtensions: .merged), format: .plantuml)
        let script = DiagramScript(items: items, configuration: configuration).text
        #expect(Self.edges(script) == ["P <|.. Foo : conforms to", "Q <|.. Foo : conforms to"])
    }

    @Test("a conformance a macro already gives the type is drawn once")
    func macroConformanceDrawnOnce() {
        let source = "@Observable final class Model {}\nextension Model: Observable {}"
        let drawn = Self.edges(source, .plantuml)
        #expect(drawn.filter { $0.hasPrefix("Observable ") } == ["Observable <|-- Model : inherits"], "\(drawn)")
    }

    // MARK: - Drawn as the type's own clause would draw it

    /// Each pair: an extension's conformance merged into its type, and the same conformance
    /// written on the type.
    static let sameAsOwnClause: [(merged: String, own: String)] = [
        ("final class Plain {}\nextension Plain: Sendable {}", "final class Plain: Sendable {}"),
        ("struct Plain {}\nextension Plain: Codable {}", "struct Plain: Codable {}"),
        ("protocol P {}\nclass Plain {}\nextension Plain: P {}", "protocol P {}\nclass Plain: P {}"),
        ("enum Plain {}\nextension Plain: Sendable {}", "enum Plain: Sendable {}"),
        ("protocol P {}\nactor Plain {}\nextension Plain: P {}", "protocol P {}\nactor Plain: P {}")
    ]

    @Test("a merged conformance is drawn exactly as the type's own clause draws it", arguments: textFormats)
    func drawnLikeOwnClause(format: DiagramFormat) {
        for (merged, own) in Self.sameAsOwnClause {
            #expect(Self.edges(merged, format) == Self.edges(own, format), "\(merged)")
            #expect(!Self.edges(merged, format).isEmpty, "\(merged)")
        }
    }

    // MARK: - A type the diagram does not declare

    @Test("a type the sources only extend draws every extension's conformance from its one box")
    func undeclaredExtendedType() {
        let source = "protocol P {}\nprotocol Q {}\nextension String: P {}\nextension String: Q {}"
        #expect(Self.edges(source, .plantuml) == ["P <|.. String : conforms to", "Q <|.. String : conforms to"])
        #expect(Self.edges(source, .mermaid) == ["P <|.. String : conforms to", "Q <|.. String : conforms to"])
    }

    // MARK: - Once each

    @Test("a conformance both #if clauses declare is drawn once", arguments: textFormats)
    func ifClausesDrawOnce(format: DiagramFormat) {
        let source = """
            protocol P {}
            struct Foo {}
            #if os(macOS)
            extension Foo: P {}
            #else
            extension Foo: P {}
            #endif
            """
        let single = Self.edges("protocol P {}\nstruct Foo {}\nextension Foo: P {}", format)
        #expect(single.count == 1)
        #expect(Self.edges(source, format) == single)
    }

    @Test("#if clauses that share some conformances draw each conformance once")
    func ifClausesShareSome() {
        let source = """
            protocol P {}
            protocol Q {}
            struct Foo {}
            #if DEBUG
            extension Foo: P, Q {}
            #else
            extension Foo: P {}
            #endif
            """
        #expect(Self.edges(source, .plantuml) == ["P <|.. Foo : conforms to", "Q <|.. Foo : conforms to"])
    }

    @Test("each of two extensions draws its own conformance, in the order they are written")
    func twoExtensions() {
        let source = "protocol P {}\nprotocol Q {}\nstruct Foo {}\nextension Foo: Q {}\nextension Foo: P {}"
        #expect(Self.edges(source, .plantuml) == ["Q <|.. Foo : conforms to", "P <|.. Foo : conforms to"])
    }

    // MARK: - Settings that already apply to supertypes

    @Test("realize.exclude hides a merged conformance, as it hides the type's own")
    func excluded() {
        let source = "protocol P {}\nstruct Foo {}\nextension Foo: P, Codable {}"
        let relationships = RelationshipOptions(realize: Relationship(label: "conforms to", exclude: ["Codable"]))
        for format in Self.textFormats {
            let drawn = Self.edges(source, format, relationships: relationships)
            #expect(drawn.count == 1, "\(format): \(drawn)")
            #expect(!drawn.joined().contains("Codable"), "\(format)")
        }
    }

    @Test("a suffix never takes a conformance that only a merged extension's edge names")
    func suffixSkipsCarriedConformance() {
        let source = """
            #if DEBUG
            struct P {}
            #else
            struct P {}
            #endif
            struct Bar {}
            extension Bar: P0 {}
            """
        let mermaid = Self.script(source, .mermaid)
        #expect(ClassDiagramIds.mermaid(in: mermaid) == ["P", "P1", "Bar"])
        #expect(Self.edges(mermaid) == ["P0 <|-- Bar : inherits"])
        #expect(ClassDiagramIds.plantUML(in: Self.script(source, .plantuml)) == ["P", "P1", "Bar"])
    }

    @Test("hidden extensions still draw no conformance")
    func hiddenExtensions() {
        let source = "protocol P {}\nstruct Foo {}\nextension Foo: P {}"
        for format in Self.textFormats {
            #expect(Self.edges(source, format, ExtensionVisualization.none).isEmpty, "\(format)")
        }
    }
}
