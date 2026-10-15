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

    /// Each edge as `[start, arrow, end]`.
    private func edges(_ graph: NomnomlGraph) -> [[String]] {
        graph.edges.map { [$0.start, $0.type, $0.end] }
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
        #expect(edges(repeated) == [["PlatformView", "-:>", "NSView"], ["PlatformView0", "-:>", "UIView"]])
        let extended = try nomnoml("struct Foo {}\nextension Foo: P {}\nprotocol P {}")
        #expect(edges(extended) == [["Foo0", "--:>", "P"], ["Foo0", "-->", "Foo"]])
        #expect(extended.node("Foo0")?.type == "extension")
        let twice = try nomnoml("protocol P {}\nprotocol Q {}\nextension String: P {}\nextension String: Q {}")
        #expect(edges(twice) == [["String", "--:>", "P"], ["String0", "--:>", "Q"]])
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
