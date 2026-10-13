import Testing
@testable import SwiftUMLBridgeFramework

/// Preparing class-diagram items (nesting, ordering, merging extensions) used to run twice for an
/// SVG class diagram, once for text definitions the SVG path then threw away, and preparation
/// edits the structures it is given, so merged members and nested types came out doubled (#73).
@Suite("Class-diagram preparation — once per diagram")
struct ClassDiagramPreparationTests {

    private static let merged = ElementOptions(showExtensions: .merged)

    private func items(_ source: String) -> [SyntaxStructure] {
        SyntaxStructure.create(from: source)?.substructure ?? []
    }

    /// The SVG graph `DiagramScript` builds, the path that prepared the items twice.
    private func scriptGraph(_ source: String, elements: ElementOptions = merged) -> LayoutGraph? {
        ClassDiagramGenerator()
            .generateScript(for: source, with: Configuration(elements: elements, format: .svg)).layoutGraph
    }

    /// The graph one preparation of freshly parsed items gives: what the SVG path must match.
    private func freshGraph(_ source: String, elements: ElementOptions = merged) -> LayoutGraph {
        LayoutGraphBuilder.buildClassDiagram(
            from: items(source), configuration: Configuration(elements: elements, format: .svg)
        )
    }

    private func ids(_ graph: LayoutGraph?) -> [String] { graph?.nodeIds ?? [] }

    private func members(_ graph: LayoutGraph?) -> [[String]] { graph?.memberLines ?? [] }

    private func edges(_ graph: LayoutGraph?) -> [String] { graph?.edgeEnds ?? [] }

    // MARK: - The SVG Path Prepares Once

    @Test("a merged extension's members are listed once")
    func mergedMembersListedOnce() {
        let source = "struct Foo { var count: Int }\nextension Foo { func bar() {} }"
        #expect(members(scriptGraph(source)) == [["~ count: Int", "~ bar()"]])
        #expect(members(freshGraph(source)) == [["~ count: Int", "~ bar()"]])
    }

    @Test("a type nested in a merged extension is drawn once")
    func nestedTypeInMergedExtensionDrawnOnce() {
        let source = "struct Foo {}\nextension Foo { struct Inner {} }"
        #expect(ids(scriptGraph(source)) == ["Foo", "Foo.Inner"])
        #expect(edges(scriptGraph(source)) == ["Foo -> Foo.Inner"])
        #expect(edges(freshGraph(source)) == ["Foo -> Foo.Inner"])
    }

    struct MergedCase: Sendable, CustomTestStringConvertible {
        let source: String
        let ids: [String]
        let members: [[String]]
        let edges: [String]

        init(_ source: String, ids: [String], members: [[String]], edges: [String] = []) {
            self.source = source
            self.ids = ids
            self.members = members
            self.edges = edges
        }

        var testDescription: String { source }
    }

    /// Each case's SVG graph must equal one preparation of freshly parsed items, and pin that result.
    static let mergedCases: [MergedCase] = [
        // Two extensions and no type: the first extension receives the second, with no suffix.
        MergedCase("extension Foo { func bar() {} }\nextension Foo { func baz() {} }",
                   ids: ["Foo"], members: [["~ bar()", "~ baz()"]]),
        // An extension of a nested type merges through the parent links nesting sets.
        MergedCase("struct Foo { struct Inner {} }\nextension Foo.Inner { func bar() {} }",
                   ids: ["Foo", "Foo.Inner"], members: [[], ["~ bar()"]], edges: ["Foo -> Foo.Inner"]),
        // A type nested in an extension of an extension-only type hangs off the first extension.
        MergedCase("extension Foo { func a() {} }\nextension Foo { struct Inner {} }",
                   ids: ["Foo.Inner", "Foo"], members: [[], ["~ a()"]], edges: ["Foo -> Foo.Inner"]),
        // A protocol receives its extension like any other type.
        MergedCase("protocol P { func a() }\nextension P { func b() {} }",
                   ids: ["P"], members: [["~ a()", "~ b()"]]),
        // An enum keeps its cases ahead of the merged members.
        MergedCase("enum Dir { case north }\nextension Dir { func flip() {} }",
                   ids: ["Dir"], members: [["north", "~ flip()"]]),
        // A type nested in an extension, then extended itself.
        MergedCase("struct Foo {}\nextension Foo { struct Inner {} }\nextension Foo.Inner { func x() {} }",
                   ids: ["Foo", "Foo.Inner"], members: [[], ["~ x()"]], edges: ["Foo -> Foo.Inner"]),
        // Deep nesting: every child keeps pointing at its own parent.
        MergedCase("struct A { struct B { struct C {} } }\n"
                   + "extension A.B { func m() {} }\nextension A.B.C { func n() {} }",
                   ids: ["A", "A.B", "A.B.C"], members: [[], ["~ m()"], ["~ n()"]],
                   edges: ["A -> A.B", "A.B -> A.B.C"])
    ]

    @Test("the SVG path matches one preparation", arguments: Self.mergedCases)
    func svgMatchesOnePreparation(expected: MergedCase) {
        for graph in [scriptGraph(expected.source), freshGraph(expected.source)] {
            #expect(ids(graph) == expected.ids)
            #expect(members(graph) == expected.members)
            #expect(edges(graph) == expected.edges)
        }
    }

    @Test("with nested types hidden, a type nested in a merged extension is not drawn")
    func nestedTypesHiddenUnderMerge() {
        let elements = ElementOptions(showNestedTypes: false, showExtensions: .merged)
        let source = "struct Foo { var count: Int }\nextension Foo { func bar() {} struct Inner {} }"
        #expect(ids(scriptGraph(source, elements: elements)) == ["Foo"])
        #expect(members(scriptGraph(source, elements: elements)) == [["~ count: Int", "~ bar()"]])
    }
}
