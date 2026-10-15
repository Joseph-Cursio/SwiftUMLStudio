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
            ? ["] -:> ", "] --:> ", "] --> "]
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
            "[Circle] -:> inherits [Base]",
            "[Circle] --:> conforms to [Shape]",
            "[Point] --:> conforms to [Shape]",
            "[Point0] --> ext [Point]"
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

    /// A `relationships:` block without an `inheritance:` key decodes it as `nil`; `realize.exclude`
    /// must still apply.
    @Test("realize.exclude applies when inheritance is not configured")
    func realizeExcludeWithoutInheritance() {
        let config = Configuration(relationships: RelationshipOptions(
            inheritance: nil, realize: Relationship(exclude: ["Codable", "Sendable"])
        ))
        let text = script(Self.model, config)
        #expect(!text.contains("Codable") && !text.contains("Sendable"))
        #expect(text.contains("Base <|-- Circle"))
    }

    @Test("realize.exclude reaches macro conformances and each part of a composition")
    func realizeReachesSyntheticAndSplitParents() {
        #expect(edges("@Observable class Store {}", configuration(realize: ["Observable"])).isEmpty)
        let composed = "protocol Shape {}\nstruct Comp: Shape & Codable {}"
        #expect(edges(composed, configuration(realize: ["Codable"])) == ["Shape <|.. Comp : conforms to"])
    }

    // MARK: - Extension Edges

    @Test("dependency.exclude hides an extension edge and moves no id", arguments: [DiagramFormat.plantuml, .mermaid])
    func dependencyExcludeKeepsIds(format: DiagramFormat) {
        let source = "struct Point {}\nextension Point {}\nstruct Pair {}\nextension Pair {}"
        let hidden = script(source, configuration(dependency: ["Poi*"], format: format))
        let shown = script(source, configuration(format: format))
        let ids = format == .mermaid ? ClassDiagramIds.mermaid(in:) : ClassDiagramIds.plantUML(in:)
        #expect(ClassDiagramIds.lines(of: hidden, containing: " <.. ") == ["Pair <.. Pair1 : ext"])
        #expect(ids(hidden) == ids(shown))
        #expect(ids(hidden) == ["Point", "Pair", "Point0", "Pair1"])
    }

    @Test("dependency.exclude leaves an extension's own conformance")
    func dependencyExcludeKeepsConformance() {
        let lines = edges("struct Point {}\nextension Point: Hashable {}", configuration(dependency: ["Point"]))
        #expect(lines == ["Hashable <.. Point0 : inherits"])
    }

    /// Each list keeps to its own edges: a supertype list never hides an extension edge, and
    /// `dependency.exclude` never hides a supertype or conformance edge to the same name.
    @Test("a supertype list leaves extension edges", arguments: [false, true])
    func supertypeListLeavesExtensionEdge(viaRealize: Bool) {
        let config = viaRealize ? configuration(realize: ["Point"]) : configuration(inheritance: ["Point"])
        #expect(edges(Self.model, config) == edges(Self.model, configuration()))
        #expect(edges(Self.model, config).contains("Point <.. Point0 : ext"))
    }

    @Test("dependency.exclude leaves conformances to the extended protocol")
    func dependencyExcludeLeavesSupertypeEdges() {
        let source = "protocol Shape {}\nstruct Circle: Shape {}\nextension Shape {}"
        #expect(edges(source, configuration(dependency: ["Shape"])) == ["Shape <|.. Circle : conforms to"])
        #expect(edges(source, configuration()) == ["Shape <|.. Circle : conforms to", "Shape <.. Shape0 : ext"])
    }

    @Test("dependency.exclude changes nothing when extensions are merged or hidden", arguments: [
        ExtensionVisualization.merged, .none
    ])
    func dependencyExcludeIdleWithoutExtensionBoxes(extensions: ExtensionVisualization) {
        let excluded = edges(Self.model, configuration(dependency: ["Point"], extensions: extensions))
        #expect(excluded == edges(Self.model, configuration(extensions: extensions)))
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
