import Testing
@testable import SwiftUMLBridgeFramework

/// The SVG class-diagram path gives every node its own id, and resolves each edge end to the
/// node that declares it (#55). The dagre layout keys nodes by id, so a shared id puts two
/// boxes in one place.
@Suite("LayoutGraphBuilder — distinct node ids and edge ends")
struct LayoutGraphBuilderNodeIdTests {

    private func graph(
        for source: String,
        extensions: ExtensionVisualization = .all
    ) -> LayoutGraph {
        LayoutGraphBuilder.buildClassDiagram(
            from: SyntaxStructure.create(from: source)?.substructure ?? [],
            configuration: Configuration(elements: ElementOptions(showExtensions: extensions), format: .svg)
        )
    }

    private func edges(for source: String) -> [String] {
        graph(for: source).edges.map { "\($0.sourceId) -> \($0.targetId)" }
    }

    static let collidingSources = [
        // The fourth declaration of a name reused the second one's id.
        "struct Foo {}\nextension Foo {}\nextension Foo {}\nextension Foo {}",
        // No type declaration is needed.
        String(repeating: "extension String {}\n", count: 4),
        // Many repeats cycled through three ids.
        "struct Foo {}\n" + String(repeating: "extension Foo {}\n", count: 6),
        // A suffix equal to a name declared later, by an extension of an undeclared type.
        "struct Foo {}\nextension Foo {}\nextension Foo_1 {}"
    ]

    @Test("every node gets a distinct id", arguments: collidingSources)
    func nodeIdsAreDistinct(source: String) {
        let ids = graph(for: source).nodes.map(\.id)
        #expect(Set(ids).count == ids.count, "node ids: \(ids)")
    }

    @Test("a type's third extension gets an id of its own")
    func thirdExtensionGetsItsOwnId() {
        #expect(graph(for: Self.collidingSources[0]).nodes.map(\.id) == ["Foo", "Foo_1", "Foo_2", "Foo_3"])
    }

    @Test("a declared name keeps its id; a repeat's suffix steps over it")
    func suffixSkipsLaterDeclaredName() {
        #expect(graph(for: Self.collidingSources[3]).nodes.map(\.id) == ["Foo", "Foo_2", "Foo_1"])
    }

    @Test("ids that did not collide keep their spelling")
    func nonCollidingIdsAreUnchanged() {
        #expect(graph(for: "struct Foo {}\nextension Foo {}\nextension Foo {}").nodes.map(\.id)
            == ["Foo", "Foo_1", "Foo_2"])
    }

    @Test("each name numbers its repeats from 1")
    func suffixCounterIsPerName() {
        #expect(graph(for: "struct Foo {}\nstruct Bar {}\nextension Foo {}\nextension Bar {}").nodes.map(\.id)
            == ["Foo", "Bar", "Foo_1", "Bar_1"])
    }

    @Test("a nested type's qualified name is reserved")
    func nestedQualifiedNameIsReserved() {
        let source = "struct Outer { struct Inner {} }\n"
            + "extension Outer {\n    struct Inner {}\n    struct Inner_1 {}\n}"
        #expect(graph(for: source).nodes.map(\.id)
            == ["Outer", "Outer.Inner", "Outer.Inner_2", "Outer.Inner_1", "Outer_1"])
    }

    @Test("a name the diagram does not draw is not reserved")
    func undrawnNameIsNotReserved() {
        let items = [
            SyntaxStructure(kind: .struct, name: "Foo"),
            SyntaxStructure(kind: .extension, name: "Foo"),
            SyntaxStructure(kind: .varGlobal, name: "Foo_1")
        ]
        #expect(LayoutGraphBuilder.buildClassDiagram(from: items, configuration: .default).nodes.map(\.id)
            == ["Foo", "Foo_1"])
    }

    @Test("dagre lays out the colliding diagram with no two nodes at one centre")
    func laidOutNodesDoNotOverlap() throws {
        let graph = graph(for: Self.collidingSources[0])
        let laidOut = DagreLayoutEngine.layout(graph)
        // The grid fallback never overlaps, so it would pass this test without dagre running.
        try #require(laidOut.fallbackReason == nil)
        #expect(laidOut.nodes.count == 4)
        let centres = laidOut.nodes.map { "\($0.posX),\($0.posY)" }
        #expect(Set(centres).count == centres.count, "centres: \(centres)")
    }

    // MARK: - Edge ends

    @Test("an inheritance edge ends at the type, not at its extension")
    func inheritanceEdgeTargetsTheType() {
        #expect(edges(for: "class Base {}\nextension Base {}\nclass Sub: Base {}") == ["Sub -> Base"])
    }

    @Test("an edge to an undeclared name never lands on a generated id")
    func undeclaredTargetIsNotMatchedAgainstIds() {
        // `Foo_1` is the id of Foo's extension, but nothing named Foo_1 is declared.
        #expect(edges(for: "struct Foo {}\nextension Foo {}\nclass C: Foo_1 {}").isEmpty)
    }

    @Test("a composition edge ends at the nested type, not at its extension")
    func compositionEdgeTargetsTheNestedType() {
        #expect(edges(for: "struct Outer { struct Inner {} }\nextension Outer.Inner {}") == ["Outer -> Outer.Inner"])
    }

    @Test("a type nested in an extension hangs off the type it extends")
    func typeNestedInExtensionHangsOffTheType() {
        #expect(edges(for: "struct Foo {}\nextension Foo { struct Inner {} }") == ["Foo -> Foo.Inner"])
    }

    @Test("the second of two same-named types keeps its own nested types")
    func nestedTypesHangOffTheirOwnDeclaration() {
        #expect(edges(for: "struct Fixture { struct Row {} }\nstruct Fixture { enum Kind {} }")
            == ["Fixture -> Fixture.Row", "Fixture_1 -> Fixture.Kind"])
    }

    @Test("a doubly nested type hangs off its qualified parent")
    func doublyNestedCompositionUsesQualifiedParent() {
        #expect(edges(for: "struct A { struct B { struct C {} } }") == ["A -> A.B", "A.B -> A.B.C"])
    }

    @Test("a nested type's edge is drawn when its parent sorts after it")
    func compositionEdgeToLaterParent() {
        // Extensions sort last, so the extension of an undeclared type follows its nested type.
        #expect(edges(for: "extension Foo { struct Inner {} }") == ["Foo -> Foo.Inner"])
    }

    @Test("edges keep declaration order")
    func edgeOrderFollowsDeclarations() {
        #expect(edges(for: "class Base {}\nstruct Outer { struct Inner {} }\nclass Sub: Base {}")
            == ["Outer -> Outer.Inner", "Sub -> Base"])
    }

    @Test("an extension's conformance edge starts at the extension")
    func extensionConformanceStartsAtTheExtension() {
        #expect(edges(for: "protocol P {}\nstruct Foo {}\nextension Foo: P {}") == ["Foo_1 -> P"])
    }

    @Test("merged extensions leave one node per name and the same edge ends")
    func mergedExtensionsKeepEdgeEnds() {
        let merged = graph(for: "class Base {}\nextension Base {}\nclass Sub: Base {}", extensions: .merged)
        #expect(merged.nodes.map(\.id) == ["Base", "Sub"])
        #expect(merged.edges.map { "\($0.sourceId) -> \($0.targetId)" } == ["Sub -> Base"])
    }
}
