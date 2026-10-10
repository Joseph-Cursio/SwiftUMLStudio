import Testing
@testable import SwiftUMLBridgeFramework

@Suite("DiagramIdentifiers")
struct DiagramIdentifiersTests {

    // MARK: - The table itself

    @Test("a name keeps its sanitized identifier when nothing collides")
    func noCollisionKeepsSanitizedText() {
        var ids = DiagramIdentifiers(sanitize: DepsScript.mermaidId)
        #expect(ids.id(for: "Outer.Inner") == "Outer_Inner")
        #expect(ids.id(for: "Array<Int>") == "Array_Int_")
    }

    @Test("asking for the same name twice returns the same identifier")
    func repeatedLookupIsStable() {
        var ids = DiagramIdentifiers(sanitize: DepsScript.mermaidId)
        let first = ids.id(for: "Outer.Inner")
        _ = ids.id(for: "Outer_Inner")
        #expect(ids.id(for: "Outer.Inner") == first)
    }

    @Test("the first name keeps the identifier and a colliding name gets a suffix")
    func collisionGetsSuffix() {
        var ids = DiagramIdentifiers(sanitize: DepsScript.mermaidId)
        #expect(ids.id(for: "Outer.Inner") == "Outer_Inner")
        #expect(ids.id(for: "Outer_Inner") == "Outer_Inner_2")
        #expect(ids.id(for: "Outer-Inner") == "Outer_Inner_3")
    }

    @Test("a suffix already claimed by a real name is skipped")
    func suffixSkipsClaimedIdentifier() {
        var ids = DiagramIdentifiers(sanitize: DepsScript.mermaidId)
        #expect(ids.id(for: "x.y") == "x_y")
        #expect(ids.id(for: "x_y_2") == "x_y_2")
        #expect(ids.id(for: "x-y") == "x_y_3")
    }

    /// Exhaustive over every name of up to three characters drawn from the characters the
    /// sanitizers rewrite: distinct names always get distinct identifiers.
    @Test("distinct names never share an identifier", arguments: [
        DepsScript.mermaidId as @Sendable (String) -> String,
        ComponentScript.safeAlias as @Sendable (String) -> String
    ])
    func distinctNamesGetDistinctIdentifiers(sanitize: @escaping @Sendable (String) -> String) {
        let alphabet = ["a", "_", "-", ".", " ", "<", ">", "+"]
        var names = [""]
        var all: [String] = []
        for _ in 1...3 {
            names = names.flatMap { prefix in alphabet.map { prefix + $0 } }
            all += names
        }
        var ids = DiagramIdentifiers(sanitize: sanitize)
        let assigned = all.map { ids.id(for: $0) }
        #expect(Set(assigned).count == all.count)
    }

    // MARK: - Emitters

    @Test("Deps Mermaid draws two names that sanitize alike as two nodes")
    func depsMermaidKeepsCollidingNodesApart() {
        let model = DependencyGraphModel(edges: [
            DependencyEdge(from: "App", to: "Outer.Inner", kind: .inherits),
            DependencyEdge(from: "Tool", to: "Outer_Inner", kind: .inherits)
        ])
        var config = Configuration.default
        config.format = .mermaid
        let text = DepsScript(model: model, configuration: config).text
        #expect(text.contains("Outer_Inner[\"Outer.Inner\"]"))
        #expect(text.contains("Outer_Inner_2[\"Outer_Inner\"]"))
        #expect(text.contains("App --> Outer_Inner\n"))
        #expect(text.contains("Tool --> Outer_Inner_2"))
    }

    @Test("Component PlantUML keeps two names that sanitize alike as two components")
    func componentPlantUMLKeepsCollidingComponentsApart() {
        let model = ComponentModel(
            components: [
                Component(name: "swift-syntax", kind: .library),
                Component(name: "swift_syntax", kind: .library)
            ],
            dependencies: [ComponentDependency(from: "swift_syntax", to: "swift-syntax")]
        )
        let text = ComponentScript(model: model, configuration: .default).text
        #expect(text.contains("component \"swift-syntax\" as swift_syntax "))
        #expect(text.contains("component \"swift_syntax\" as swift_syntax_2 "))
        #expect(text.contains("swift_syntax_2 ..> swift_syntax\n"))
    }

    @Test("Component Mermaid keeps an interface apart from a component named like it")
    func componentMermaidKeepsInterfaceApartFromComponent() {
        let model = ComponentModel(
            components: [
                Component(name: "A", kind: .library, providedInterfaces: ["B"]),
                Component(name: "A_B", kind: .library)
            ],
            dependencies: [ComponentDependency(from: "A_B", to: "A")]
        )
        var config = Configuration.default
        config.format = .mermaid
        let text = ComponentScript(model: model, configuration: config).text
        #expect(text.contains("A_B[\"B\"]"))
        #expect(text.contains("subgraph A_B_2[\"A_B\"]"))
        #expect(text.contains("A_B_2 -.-> A"))
    }
}
