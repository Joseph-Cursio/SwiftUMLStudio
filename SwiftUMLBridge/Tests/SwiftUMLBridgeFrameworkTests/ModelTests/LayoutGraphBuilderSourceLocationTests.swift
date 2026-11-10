@testable import SwiftUMLBridgeFramework
import Testing

@Suite("LayoutGraphBuilder copies sourceLocation onto nodes")
struct LayoutGraphBuilderSourceLocationTests {

    @Test("buildClassDiagram populates sourceLocation from items")
    func copiesFromItem() throws {
        let item = SyntaxStructure(kind: .class, name: "Foo")
        item.sourceLocation = SourceLocation(filePath: "/Foo.swift", line: 7, column: 1)

        let graph = LayoutGraphBuilder.buildClassDiagram(
            from: [item],
            configuration: .default
        )
        let node = try #require(graph.nodes.first)
        #expect(node.sourceLocation == SourceLocation(filePath: "/Foo.swift", line: 7, column: 1))
    }

    @Test("buildClassDiagram leaves sourceLocation nil when item has none")
    func nilWhenItemMissing() throws {
        let item = SyntaxStructure(kind: .class, name: "Foo")
        let graph = LayoutGraphBuilder.buildClassDiagram(
            from: [item],
            configuration: .default
        )
        let node = try #require(graph.nodes.first)
        #expect(node.sourceLocation == nil)
    }

    @Test("buildDependencyGraph emits nodes with no sourceLocation")
    func dependencyGraphHasNoLocation() throws {
        let model = DependencyGraphModel(
            edges: [DependencyEdge(from: "A", to: "B", kind: .imports)]
        )
        let graph = LayoutGraphBuilder.buildDependencyGraph(from: model)
        for node in graph.nodes {
            #expect(node.sourceLocation == nil)
        }
    }
}
