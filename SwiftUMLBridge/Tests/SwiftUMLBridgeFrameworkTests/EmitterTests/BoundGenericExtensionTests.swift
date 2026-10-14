import Testing
@testable import SwiftUMLBridgeFramework

/// A source whose extensions are spelled with generic arguments or sugar, beside the same source
/// with each extension spelled as the `where` clause it is shorthand for (SE-0361).
struct BoundSpelling: Sendable, CustomTestStringConvertible {
    let declarations: String
    let bound: String
    let constrained: String

    var boundSource: String { declarations + "\n" + bound }
    var constrainedSource: String { declarations + "\n" + constrained }
    var testDescription: String { bound }
}

/// The class diagram draws `extension Foo<Int>` exactly as it draws `extension Foo where T == Int`,
/// and `[Int]`, `[String: Int]` and `Int?` as `Array`, `Dictionary` and `Optional`: named, aliased,
/// linked and merged as the base type, with the generic arguments not shown (#66).
@Suite("Class diagram: extension of a bound generic type")
struct BoundGenericExtensionTests {

    static let spellings: [BoundSpelling] = [
        BoundSpelling(
            declarations: "struct Foo<T> {}",
            bound: "extension Foo<Int> {}",
            constrained: "extension Foo where T == Int {}"
        ),
        BoundSpelling(
            declarations: "struct Foo<T> {}",
            bound: "extension Foo<Swift.Int> { func f() {} }",
            constrained: "extension Foo where T == Swift.Int { func f() {} }"
        ),
        BoundSpelling(
            declarations: "struct Foo<T> {}\nstruct Bar {}",
            bound: "extension Foo<Int> {}\nextension Foo<String> { func f() {} }\nextension Bar {}",
            constrained: """
            extension Foo where T == Int {}
            extension Foo where T == String { func f() {} }
            extension Bar {}
            """
        ),
        BoundSpelling(
            declarations: "protocol P {}\nstruct Foo<T> {}",
            bound: "extension Foo<Int>: P { struct Inner {} }",
            constrained: "extension Foo: P where T == Int { struct Inner {} }"
        ),
        BoundSpelling(
            declarations: "struct Outer<A> { struct Inner<B> {} }",
            bound: "extension Outer<Int>.Inner<String> { func f() {} }",
            constrained: "extension Outer.Inner where A == Int, B == String { func f() {} }"
        ),
        BoundSpelling(
            declarations: "",
            bound: """
            extension [Int] {}
            extension [String: Int] {}
            extension Int? {}
            extension Swift.Array<Int> {}
            """,
            constrained: """
            extension Array where Element == Int {}
            extension Dictionary where Key == String, Value == Int {}
            extension Optional where Wrapped == Int {}
            extension Swift.Array where Element == Int {}
            """
        )
    ]

    static let modes: [ExtensionVisualization] = [.all, .merged, .none]
    static let formats: [DiagramFormat] = [.plantuml, .mermaid, .nomnoml, .svg]
    static let renderings: [(DiagramFormat, ExtensionVisualization)] = formats.flatMap { format in
        modes.map { (format, $0) }
    }

    /// A Swift identifier, or a dotted path of them as a nested type is declared under.
    static func isPlainIdentifier(_ identifier: String) -> Bool {
        identifier.wholeMatch(of: /[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*/) != nil
    }

    @Test("draws exactly what the `where` spelling draws", arguments: spellings, renderings)
    func matchesConstrainedSpelling(spelling: BoundSpelling, rendering: (DiagramFormat, ExtensionVisualization)) {
        let elements = ElementOptions(showExtensions: rendering.1)
        let bound = ClassDiagramIds.script(for: spelling.boundSource, format: rendering.0, elements: elements)
        let constrained = ClassDiagramIds.script(
            for: spelling.constrainedSource, format: rendering.0, elements: elements
        )
        #expect(bound == constrained)
    }

    // MARK: - The issue's symptoms, one by one

    @Test("1. Mermaid declares every element under a plain identifier", arguments: spellings, modes)
    func mermaidIdsArePlain(spelling: BoundSpelling, extensions: ExtensionVisualization) {
        let elements = ElementOptions(showExtensions: extensions)
        let ids = ClassDiagramIds.mermaid(for: spelling.boundSource, elements: elements)
        #expect(ids.allSatisfy(Self.isPlainIdentifier), "\(ids)")
    }

    @Test("2. PlantUML declares each extension under a plain id of its own", arguments: spellings)
    func plantUMLIdsArePlainAndDistinct(spelling: BoundSpelling) {
        let script = ClassDiagramIds.script(for: spelling.boundSource, format: .plantuml)
        // `ClassDiagramIds.plantUML` stops an id at `<`, as PlantUML does, so read the whole alias too.
        let ids = ClassDiagramIds.plantUML(in: script)
        let extensionAliases = ClassDiagramIds.lines(of: script, containing: " extension >>").compactMap { line in
            line.range(of: " as ").map { String(line[$0.upperBound...].prefix { $0 != " " }) }
        }
        #expect(Set(ids).count == ids.count, "\(ids)")
        #expect(ids.allSatisfy(Self.isPlainIdentifier), "\(ids)")
        #expect(extensionAliases.allSatisfy(Self.isPlainIdentifier), "\(extensionAliases)")
    }

    @Test("3. the extension is linked to the type it extends", arguments: [DiagramFormat.plantuml, .mermaid])
    func extensionEdgeIsDrawn(format: DiagramFormat) {
        let script = ClassDiagramIds.script(for: "struct Foo<T> {}\nextension Foo<Int> {}", format: format)
        #expect(ClassDiagramIds.lines(of: script, containing: ": ext") == ["Foo <.. Foo0 : ext"], "\(script)")
    }

    @Test("4. merged extensions fold into the type; a hidden one's nested type keeps a plain id")
    func mergedAndHidden() {
        let source = "struct Foo<T> {}\nextension Foo<Int> { func f() {} struct Inner {} }"
        let merged = ClassDiagramIds.mermaid(for: source, elements: ElementOptions(showExtensions: .merged))
        let hidden = ClassDiagramIds.mermaid(for: source, elements: ElementOptions(showExtensions: .some(.none)))
        #expect(merged == ["Foo", "Foo.Inner"])
        #expect(hidden == ["Foo", "Foo.Inner"])
    }

    @Test("5. a qualified argument leaves the label alone")
    func labelIsTheTypeName() throws {
        let source = "struct Foo<T> {}\nextension Foo<Swift.Int> {}"
        let plantUML = ClassDiagramIds.script(for: source, format: .plantuml)
        let mermaid = ClassDiagramIds.script(for: source, format: .mermaid)
        let nomnoml = ClassDiagramIds.script(for: source, format: .nomnoml)
        let items = try #require(SyntaxStructure.create(from: source)?.substructure)
        let svg = LayoutGraphBuilder.buildClassDiagram(from: items, configuration: Configuration(format: .svg))
        #expect(plantUML.contains("class \"Foo\" as Foo0 << (X, orchid) extension >>"), "\(plantUML)")
        #expect(mermaid.contains("class Foo0[\"Foo\"] {"), "\(mermaid)")
        #expect(nomnoml.contains("[<extension> Foo]"), "\(nomnoml)")
        #expect(svg.nodes.map(\.label) == ["Foo", "Foo"])
    }

    /// `elements.exclude` matches an extension by the type it extends, as for the `where` spelling.
    @Test("excluding a type excludes its bound and sugared extensions")
    func excludedWithItsType() {
        let source = "struct Foo<T> {}\nstruct Bar {}\nextension Foo<Int> {}\nextension [Int] {}"
        #expect(ClassDiagramIds.mermaid(for: source, elements: ElementOptions(exclude: ["Foo", "Array"])) == ["Bar"])
    }

    @Test("6. edges carry no generic arguments", arguments: [DiagramFormat.plantuml, .mermaid, .nomnoml])
    func edgesCarryNoArguments(format: DiagramFormat) {
        let source = "protocol P {}\nstruct Foo<T> {}\nextension Foo<Int>: P { struct Inner {} }"
        let script = ClassDiagramIds.script(for: source, format: format)
        #expect(ClassDiagramIds.lines(of: script, containing: "<Int>").isEmpty, "\(script)")
        if format == .plantuml {
            #expect(script.contains("Foo0 +-- Foo.Inner"), "\(script)")
        }
    }
}
