import Testing
@testable import SwiftUMLBridgeFramework

/// An SVG class diagram draws an extension's box with an edge to the type it extends, as the text
/// formats' `ext` edge does (#75), and draws none where they draw none.
@Suite("SVG class diagram: extension edges")
struct SVGExtensionEdgeTests {

    private func svgEdges(
        _ source: String, _ extensions: ExtensionVisualization = .all,
        relationships: RelationshipOptions = RelationshipOptions()
    ) -> [String] {
        let graph = classDiagram(source, .svg, extensions, relationships: relationships).layoutGraph
        return graph?.edges.map { "\($0.sourceId) -> \($0.targetId) \($0.style)" } ?? []
    }

    @Test("an extension of a declared type gets a dependency edge to that type")
    func extensionPointsAtExtendedType() {
        #expect(svgEdges("struct Foo {}\nextension Foo {}") == ["Foo_1 -> Foo dependency"])
    }

    @Test("every extension of a declared type points at the type, not at another extension")
    func everyExtensionPointsAtExtendedType() {
        #expect(svgEdges("struct Foo {}\nextension Foo {}\nextension Foo {}")
            == ["Foo_1 -> Foo dependency", "Foo_2 -> Foo dependency"])
    }

    @Test("an extension of a nested type points at the nested type")
    func extensionOfNestedType() {
        #expect(svgEdges("struct Outer { struct Inner {} }\nextension Outer.Inner {}")
            == ["Outer -> Outer.Inner composition", "Outer.Inner_1 -> Outer.Inner dependency"])
    }

    @Test("an extension of a type outside the diagram gets no edge", arguments: [
        "extension String {}\nextension String {}",
        "extension [Int] {}"
    ])
    func noEdgeForUndeclaredType(source: String) {
        #expect(svgEdges(source).isEmpty)
    }

    /// The type is `fileprivate`, which the default access levels hide; its extension stands in for
    /// it, as in the text formats, and so has no edge to draw.
    @Test("an extension of a hidden type gets no edge")
    func noEdgeForHiddenType() {
        #expect(svgEdges("fileprivate struct Foo {}\nextension Foo {}").isEmpty)
    }

    @Test("merged and hidden extensions draw no extension edge", arguments: [ExtensionVisualization.merged, .none])
    func noEdgeWhenNotDrawnApart(extensions: ExtensionVisualization) {
        #expect(svgEdges("struct Foo {}\nextension Foo {}", extensions).isEmpty)
    }

    /// `dependency.exclude` hides only the edge, matched against the extension's name as written
    /// and against the type's name as declared (#113, #124).
    @Test("relationships.dependency.exclude hides the edge", arguments: ["Foo", "Outer.Foo", "Outer.*"])
    func dependencyExcludeHidesEdge(pattern: String) {
        let source = "struct Outer { struct Foo {} }\nextension Outer.Foo {}"
        let relationships = RelationshipOptions(dependency: Relationship(exclude: [pattern]))
        #expect(svgEdges(source, relationships: relationships) == ["Outer -> Outer.Foo composition"])
    }

    /// Mermaid draws `Foo <.. Foo0 : ext` for each extension SVG draws an edge from.
    @Test("SVG draws an extension edge wherever Mermaid draws one", arguments: [
        "struct Foo {}\nextension Foo {}",
        "struct Foo {}\nextension Foo {}\nextension Foo {}",
        "class Base {}\nextension Base {}\nclass Sub: Base {}",
        "struct Outer { struct Inner {} }\nextension Outer.Inner {}",
        "struct Foo<T> {}\nextension Foo<Int> {}",
        "struct Real {}\ntypealias Alias = Real\nextension Alias {}",
        "extension String {}\nextension String {}",
        "fileprivate struct Foo {}\nextension Foo {}"
    ])
    func agreesWithMermaid(source: String) {
        let mermaid = classDiagram(source, .mermaid).text.split(separator: "\n").filter { $0.hasSuffix(" : ext") }
        let svg = svgEdges(source).filter { $0.hasSuffix(" dependency") }
        #expect(svg.count == mermaid.count, "\(svg) vs \(mermaid)")
    }
}
