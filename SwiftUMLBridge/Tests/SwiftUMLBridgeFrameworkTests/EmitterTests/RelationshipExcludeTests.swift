import Testing
@testable import SwiftUMLBridgeFramework

/// `relationships.realize.exclude` and `relationships.dependency.exclude` were decoded but never
/// read, so the documented `realize.exclude: [Codable, Sendable]` hid nothing (#113).
@Suite("Class diagram — relationship excludes")
struct RelationshipExcludeTests {

    /// The issue's sample: a declared superclass and protocol, plus `Codable` and `Sendable`,
    /// which the diagram does not declare and so draws as inheritance.
    static let model = """
    protocol Shape {}
    class Base {}
    class Circle: Base, Shape, Codable {}
    struct Point: Shape, Sendable {}
    extension Point { func moved() {} }
    """

    private func configuration(
        inheritance: [String]? = nil,
        realize: [String]? = nil,
        dependency: [String]? = nil,
        format: DiagramFormat = .plantuml,
        extensions: ExtensionVisualization? = nil
    ) -> Configuration {
        Configuration(
            elements: ElementOptions(showExtensions: extensions),
            relationships: RelationshipOptions(
                inheritance: Relationship(label: "inherits", exclude: inheritance),
                realize: Relationship(label: "conforms to", exclude: realize),
                dependency: Relationship(label: "ext", exclude: dependency)
            ),
            format: format
        )
    }

    private func script(_ source: String, _ configuration: Configuration) -> String {
        ClassDiagramGenerator().generateScript(for: source, with: configuration).text
    }

    /// The relationship lines of a PlantUML, Mermaid or Nomnoml class diagram, in order.
    private func edges(_ source: String, _ configuration: Configuration) -> [String] {
        let arrows = configuration.format == .nomnoml
            ? ["] -:> [", "] --:> [", "] --> ["]
            : [" <|-- ", " <|.. ", " <.. "]
        return script(source, configuration).split(separator: "\n").map(String.init)
            .filter { line in arrows.contains { line.contains($0) } }
    }

    // MARK: - Supertype Edges

    @Test("the documented realize.exclude hides Codable and Sendable", arguments: [DiagramFormat.plantuml, .mermaid])
    func documentedRealizeExample(format: DiagramFormat) {
        let config = configuration(realize: ["Codable", "Sendable"], format: format)
        #expect(edges(Self.model, config) == [
            "Base <|-- Circle : inherits",
            "Shape <|.. Circle : conforms to",
            "Shape <|.. Point : conforms to",
            "Point <.. Point0 : ext"
        ])
    }

    @Test("the documented realize.exclude hides Codable and Sendable in Nomnoml")
    func documentedRealizeExampleNomnoml() {
        let config = configuration(realize: ["Codable", "Sendable"], format: .nomnoml)
        #expect(edges(Self.model, config) == [
            "[Circle] -:> [Base] : inherits",
            "[Circle] --:> [Shape] : conforms to",
            "[Point] --:> [Shape] : conforms to",
            "[Point0] --> [Point] : ext"
        ])
    }

    @Test("a realize.exclude glob hides conformances to a declared protocol")
    func realizeGlobOnDeclaredProtocol() {
        #expect(edges(Self.model, configuration(realize: ["Sha*"])) == [
            "Base <|-- Circle : inherits",
            "Codable <|-- Circle : inherits",
            "Sendable <|-- Point : inherits",
            "Point <.. Point0 : ext"
        ])
    }

    /// Whether the diagram draws an edge as inheritance or conformance depends on whether it
    /// declares the parent, so the two lists are pooled: either hides the same edges.
    @Test("inheritance.exclude and realize.exclude hide the same edges", arguments: [false, true])
    func supertypeListsArePooled(viaRealize: Bool) {
        let names = ["Shape", "Base"]
        let config = viaRealize ? configuration(realize: names) : configuration(inheritance: names)
        #expect(edges(Self.model, config) == [
            "Codable <|-- Circle : inherits",
            "Sendable <|-- Point : inherits",
            "Point <.. Point0 : ext"
        ])
    }

    @Test("realize.exclude reaches macro conformances and each part of a composition")
    func realizeReachesSyntheticAndSplitParents() {
        #expect(edges("@Observable class Store {}", configuration(realize: ["Observable"])).isEmpty)
        let composed = "protocol Shape {}\nstruct Comp: Shape & Codable {}"
        #expect(edges(composed, configuration(realize: ["Codable"])) == ["Shape <|.. Comp : conforms to"])
    }

    @Test("an inheritance.exclude config draws what it drew before")
    func inheritanceExcludeUnchanged() {
        #expect(edges(Self.model, configuration(inheritance: ["Shape", "Codable"])) == [
            "Base <|-- Circle : inherits",
            "Sendable <|-- Point : inherits",
            "Point <.. Point0 : ext"
        ])
    }
}
