import Testing
@testable import SwiftUMLBridgeFramework

/// nomnoml reads an edge's label only beside the arrow, as in `[A] --> label [B]`. Written after
/// the end, as the ` : label` Mermaid and PlantUML take, it reads as the start of another edge and
/// fails the whole diagram, so a Nomnoml class diagram with any labelled edge drew nothing (#69).
@Suite("Nomnoml class-diagram edge labels")
struct NomnomlEdgeLabelTests {

    /// Every edge kind the class diagram draws: inheritance, conformance, an enum's raw type, a
    /// nested type and an extension.
    static let model = """
    class Base {}
    protocol Shape {}
    final class Circle: Base, Shape {
        enum Suit: String { case hearts }
    }
    extension Circle {}
    """

    private func graph(
        _ source: String,
        _ relationships: RelationshipOptions = RelationshipOptions()
    ) throws -> NomnomlGraph {
        let configuration = Configuration(relationships: relationships, format: .nomnoml)
        return try NomnomlGraph(parsing: ClassDiagramGenerator().generateScript(for: source, with: configuration).text)
    }

    @Test("with the default labels, nomnoml parses every edge kind and shows each label by the arrow")
    func defaultLabels() throws {
        let edges = try graph(Self.model).edges
        #expect(edges.map { [$0.type, $0.endLabel] } == [
            ["-:>", "inherits"], ["--:>", "conforms to"], ["-", "inherits"], ["+-", ""], ["-->", "ext"]
        ])
        #expect(edges.allSatisfy { $0.startLabel.isEmpty })
    }

    /// A `[` would end the label, and a line break would start a line nomnoml reads before the
    /// edge: `//` drops it as a comment, `#` makes it a directive.
    @Test("a configured label reaches nomnoml whole, with brackets and line breaks escaped")
    func configuredLabels() throws {
        let relationships = RelationshipOptions(
            inheritance: Relationship(label: "is a [kind]"),
            realize: Relationship(label: "a|b; c]\n// d"),
            dependency: Relationship(label: "extends\r\n#direction: right")
        )
        let graph = try graph(Self.model, relationships)
        #expect(graph.edges.map(\.endLabel) == [
            "is a (kind)", "a|b; c) // d", "is a (kind)", "", "extends #direction: right"
        ])
        #expect(graph.edges.map(\.end) == ["Base", "Shape", "String", "Circle.Suit", "Circle"])
    }

    @Test("an edge whose label is turned off or empty has none")
    func unlabelled() throws {
        let relationships = RelationshipOptions(
            inheritance: Relationship(label: nil),
            realize: Relationship(label: ""),
            dependency: Relationship(label: nil)
        )
        let script = ClassDiagramGenerator()
            .generateScript(for: Self.model, with: Configuration(relationships: relationships, format: .nomnoml))
            .text
        #expect(script.contains("[Circle] -:> [Base]"), "\(script)")
        #expect(script.contains("[Circle] --:> [Shape]"), "\(script)")
        // A `nil` dependency label falls back to the relationship's name, as in every format.
        #expect(try NomnomlGraph(parsing: script).edges.map(\.endLabel) == ["", "", "", "", "ext"])
    }
}
