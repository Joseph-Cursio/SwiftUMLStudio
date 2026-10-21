import Testing
@testable import SwiftUMLBridgeFramework

/// A supertype edge starts at the box of the declaration that writes it (#68). The text formats
/// drew it from the first box with the declaration's name, so an extension's conformances and
/// the second branch of an `#if` hung off another box, which then claimed supertypes it never
/// wrote. A declaration's other edges, and SVG's supertype edges, already started at its own box.
@Suite("Class-diagram supertype edges start at the declaration that wrote them")
struct ClassDiagramEdgeSourceTests {

    private func lines(
        _ source: String, _ format: DiagramFormat, containing marker: String,
        extensions: ExtensionVisualization = .all
    ) -> [String] {
        let configuration = Configuration(elements: ElementOptions(showExtensions: extensions), format: format)
        return ClassDiagramIds.lines(
            of: ClassDiagramGenerator().generateScript(for: source, with: configuration).text, containing: marker
        )
    }

    private func nomnoml(_ source: String) throws -> NomnomlGraph {
        try NomnomlGraph(parsing: ClassDiagramIds.script(for: source, format: .nomnoml))
    }

    // MARK: - The issue's inputs

    static let repeatedType =
        "#if os(macOS)\nclass PlatformView: NSView {}\n#else\nclass PlatformView: UIView {}\n#endif"

    @Test("the second of two same-named classes draws its own superclass edge", arguments: [
        DiagramFormat.mermaid, .plantuml
    ])
    func repeatedTypeOwnsItsEdge(format: DiagramFormat) {
        #expect(lines(Self.repeatedType, format, containing: "<|--")
            == ["NSView <|-- PlatformView : inherits", "UIView <|-- PlatformView0 : inherits"])
    }

    @Test("an extension's conformance edge starts at the extension's box", arguments: [
        DiagramFormat.mermaid, .plantuml
    ])
    func extensionOwnsItsConformance(format: DiagramFormat) {
        let source = "struct Foo {}\nextension Foo: P {}\nprotocol P {}"
        #expect(lines(source, format, containing: "<|..") == ["P <|.. Foo0 : conforms to"])
    }

    @Test("the second extension of an undeclared type draws its own conformance edge", arguments: [
        DiagramFormat.mermaid, .plantuml
    ])
    func secondExtensionOwnsItsConformance(format: DiagramFormat) {
        let source = "protocol P {}\nprotocol Q {}\nextension String: P {}\nextension String: Q {}"
        #expect(lines(source, format, containing: "<|..")
            == ["P <|.. String : conforms to", "Q <|.. String0 : conforms to"])
    }

    // MARK: - Nomnoml

    /// Nomnoml declares each node under its alias since #69, so the raw name named the first box.
    @Test("Nomnoml starts each supertype edge at the box that wrote it")
    func nomnomlEdgesStartAtTheirDeclaration() throws {
        let repeated = try nomnoml(Self.repeatedType)
        #expect(repeated.edgeTriples == [["PlatformView", "-:>", "NSView"], ["PlatformView0", "-:>", "UIView"]])
        let extended = try nomnoml("struct Foo {}\nextension Foo: P {}\nprotocol P {}")
        #expect(extended.edgeTriples == [["Foo0", "--:>", "P"], ["Foo0", "-->", "Foo"]])
        #expect(extended.node("Foo0")?.type == "extension")
        let twice = try nomnoml("protocol P {}\nprotocol Q {}\nextension String: P {}\nextension String: Q {}")
        #expect(twice.edgeTriples == [["String", "--:>", "P"], ["String0", "--:>", "Q"]])
    }

    // MARK: - One convention per declaration

    @Test("an extension's conformance and nested type hang off the same box")
    func extensionEdgesShareItsBox() {
        let source = "struct Foo {}\nextension Foo: P { struct Inner {} }\nprotocol P {}"
        #expect(lines(source, .plantuml, containing: "Foo0")
            == ["class \"Foo\" as Foo0 << (X, orchid) extension >> {  ", "P <|.. Foo0 : conforms to",
                "Foo0 +-- Foo.Inner", "Foo <.. Foo0 : ext"])
    }

    @Test("a first declaration's edges keep its name", arguments: [DiagramFormat.mermaid, .plantuml])
    func firstDeclarationKeepsItsName(format: DiagramFormat) {
        let source = "protocol P {}\nprotocol Q {}\nstruct Foo: P {}\nextension Foo: Q {}"
        #expect(lines(source, format, containing: "<|..") == ["P <|.. Foo : conforms to", "Q <|.. Foo0 : conforms to"])
    }

    @Test("an extension that takes the next free suffix draws its edge from it")
    func skippedSuffix() {
        let source = "struct Foo0 {}\nstruct Foo {}\nextension Foo: P {}\nprotocol P {}"
        #expect(lines(source, .mermaid, containing: "<|..") == ["P <|.. Foo1 : conforms to"])
    }

    /// The repeated class has no extension, so the extension setting must not move its edge.
    @Test("a repeated type owns its edge under every extension setting", arguments: [
        ExtensionVisualization.all, .merged, .none
    ])
    func repeatedTypeUnderEveryExtensionSetting(extensions: ExtensionVisualization) {
        #expect(lines(Self.repeatedType, .mermaid, containing: "<|--", extensions: extensions)
            == ["NSView <|-- PlatformView : inherits", "UIView <|-- PlatformView0 : inherits"])
    }

    // MARK: - The declaration's own arrow

    /// A repeat took its name's first declaration's arrow, so whether `Foo` was declared, and as
    /// what, decided how `extension Foo: Codable` was drawn. An extension's supertypes are drawn
    /// as dependencies, as SVG draws them.
    @Test("an extension draws its supertypes with its own arrow, whatever it extends", arguments: [
        "struct Foo {}", "class Foo {}", "enum Foo {}", "actor Foo {}", "protocol Foo {}"
    ])
    func extensionTakesItsOwnArrow(declaration: String) throws {
        let source = "\(declaration)\nextension Foo: Codable {}"
        for format in [DiagramFormat.mermaid, .plantuml] {
            #expect(lines(source, format, containing: "Codable") == ["Codable <.. Foo0 : inherits"])
        }
        #expect(try nomnoml(source).edgeTriples == [["Foo0", "-->", "Codable"], ["Foo0", "-->", "Foo"]])
        // The same arrow as an extension of a type the diagram does not declare.
        #expect(lines("extension Foo: Codable {}", .mermaid, containing: "Codable") == ["Codable <.. Foo : inherits"])
    }

    @Test("a repeated type takes its own kind's arrow, not the first declaration's")
    func repeatedTypeTakesItsOwnArrow() throws {
        let source = "#if os(macOS)\nenum Mode: Int {}\n#else\nclass Mode: Base {}\n#endif"
        for format in [DiagramFormat.mermaid, .plantuml] {
            #expect(lines(source, format, containing: " : inherits")
                == ["Int -- Mode : inherits", "Base <|-- Mode0 : inherits"])
        }
        #expect(try nomnoml(source).edgeTriples == [["Mode", "-", "Int"], ["Mode0", "-:>", "Base"]])
    }

    /// The arrows lived in `uniqElementAndTypes` under `<name>LinkType`, beside each name's
    /// relationship. So a type named `PLinkType` overwrote protocol `P`'s arrow with its own
    /// relationship, and `struct S: P` was drawn `P inherits S`. And a supertype named
    /// `FooLinkType` read `Foo`'s arrow as its relationship, so its edge lost its label.
    @Test("no type's name changes another type's edge", arguments: [DiagramFormat.mermaid, .plantuml])
    func edgeIsNotKeyedByName(format: DiagramFormat) {
        let conformance = "protocol P {}\nstruct PLinkType {}\nstruct S: P {}"
        #expect(lines(conformance, format, containing: " : ") == ["P <|.. S : conforms to"])
        let repeated = "class Foo {}\nstruct FooLinkType {}\nextension Foo: Bar {}"
        #expect(lines(repeated, format, containing: "Bar") == ["Bar <.. Foo0 : inherits"])
        let supertype = "class Foo {}\nclass Child: FooLinkType {}"
        #expect(lines(supertype, format, containing: "FooLinkType") == ["FooLinkType <|-- Child : inherits"])
    }

    // MARK: - Agreement with SVG

    /// Inputs whose every supertype is declared, since SVG drops an edge to a type it does not
    /// draw, and with no macro, which Mermaid writes only as a comment.
    static let declaredSupertypes = [
        "class Base1 {}\nclass Base2 {}\nclass Foo: Base1 {}\nclass Foo: Base2 {}",
        "struct Foo {}\nextension Foo: P {}\nprotocol P {}",
        "protocol P {}\nprotocol Q {}\nextension String: P {}\nextension String: Q {}",
        "struct Foo {}\nextension Foo: P {}\nextension Foo: Q {}\nprotocol P {}\nprotocol Q {}",
        "protocol P {}\nprotocol R {}\nextension P: R {}",
        "struct Foo: P {}\nextension Foo: Q { struct Inner: P {} }\nprotocol P {}\nprotocol Q {}",
        "enum E: P {}\nextension E: Q {}\nprotocol P {}\nprotocol Q {}",
        "actor A {}\nextension A: P, Q {}\nprotocol P {}\nprotocol Q {}",
        "struct Foo0 {}\nstruct Foo {}\nextension Foo: P {}\nprotocol P {}"
    ]

    /// SVG lists its nodes in the order the text formats declare them, so the n-th SVG id and the
    /// n-th Mermaid or PlantUML id name one declaration.
    @Test("each supertype edge starts at the declaration SVG starts it at", arguments: declaredSupertypes)
    func agreesWithSVG(source: String) throws {
        let svg = try #require(ClassDiagramGenerator().generateScript(
            for: source, with: Configuration(format: .svg)
        ).layoutGraph)
        for format in [DiagramFormat.mermaid, .plantuml] {
            let script = ClassDiagramIds.script(for: source, format: format)
            let ids = format == .mermaid ? ClassDiagramIds.mermaid(in: script) : ClassDiagramIds.plantUML(in: script)
            try #require(ids.count == svg.nodes.count, "\(ids) vs \(svg.nodes.map(\.id))")
            let textId = Dictionary(uniqueKeysWithValues: zip(svg.nodes.map(\.id), ids))
            let expected = svg.edges.filter { $0.style != .composition }
                .map { "\(textId[$0.sourceId] ?? "?") -> \(textId[$0.targetId] ?? "?")" }
            let drawn = script.split(separator: "\n").compactMap { line -> String? in
                let words = line.split(separator: " ")
                guard words.count >= 3, ["<|--", "<|..", "<..", "--"].contains(words[1]),
                      !line.hasSuffix(" : ext") else { return nil }
                return "\(words[2]) -> \(words[0])"
            }
            #expect(drawn.sorted() == expected.sorted(), "\(format): \(script)")
        }
    }
}
