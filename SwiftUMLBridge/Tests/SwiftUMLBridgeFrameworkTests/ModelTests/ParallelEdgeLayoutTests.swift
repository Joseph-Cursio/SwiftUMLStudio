import Foundation
@testable import SwiftUMLBridgeFramework
import Testing

/// Two edges between one pair of boxes, in one direction, as a nested protocol its parent
/// conforms to has: a nesting edge and a supertype edge. dagre laid out one edge a pair, so the
/// second replaced the first, and the SVG and the Studio's canvas drew only one (#249).
@Suite("Edges between the same pair of boxes")
struct ParallelEdgeLayoutTests {
    private static let nodes = [LayoutNode(id: "Foo", label: "Foo"), LayoutNode(id: "Foo.Base", label: "Foo.Base")]

    /// The middle point of each route, which the two routes of a pair do not share.
    private func middles(of edges: [LayoutEdge]) -> [Double] {
        edges.compactMap { $0.points.isEmpty ? nil : $0.points[$0.points.count / 2].posX }
    }

    @Test("edges of two styles between one pair are each routed, apart", arguments: [nil, "App"] as [String?])
    func stylesRoutedApart(module: String?) {
        let moduleNodes = Self.nodes.map { node in
            LayoutNode(id: node.id, label: node.label, module: module)
        }
        let edges = [
            LayoutEdge(sourceId: "Foo", targetId: "Foo.Base", style: .composition),
            LayoutEdge(sourceId: "Foo", targetId: "Foo.Base", style: .realization),
        ]
        let result = DagreLayoutEngine.layout(LayoutGraph(nodes: moduleNodes, edges: edges))
        #expect(result.fallbackReason == nil)
        #expect(result.edges.allSatisfy { $0.points.count >= 2 })
        #expect(Set(middles(of: result.edges)).count == 2)
    }

    @Test("edges of one style with two labels between one pair are each routed, apart")
    func labelsRoutedApart() {
        let edges = [
            LayoutEdge(sourceId: "Foo", targetId: "Foo.Base", label: "first", style: .association),
            LayoutEdge(sourceId: "Foo", targetId: "Foo.Base", label: "second", style: .association),
            LayoutEdge(sourceId: "Foo", targetId: "Foo.Base", style: .association),
        ]
        let result = DagreLayoutEngine.layout(LayoutGraph(nodes: Self.nodes, edges: edges))
        #expect(result.edges.allSatisfy { $0.points.count >= 2 })
        #expect(Set(middles(of: result.edges)).count == 3)
    }

    /// Two edges drawn alike share one route, as before: the first is drawn, and the second,
    /// which would lie over it, is left without points.
    @Test("two edges alike between one pair share one route")
    func alikeShareRoute() {
        let edge = LayoutEdge(sourceId: "Foo", targetId: "Foo.Base", style: .dependency)
        let result = DagreLayoutEngine.layout(LayoutGraph(nodes: Self.nodes, edges: [edge, edge]))
        #expect(result.edges[0].points.count >= 2)
        #expect(result.edges[1].points.isEmpty)
    }

    /// A route goes to the edge it was laid out for, by name as well as ends: matched by ends
    /// alone, the second of two alike edges would take the route of the edge after it, and that
    /// edge would be left undrawn.
    @Test("an edge after two alike edges keeps its own route")
    func routeByName() {
        let alike = LayoutEdge(sourceId: "Foo", targetId: "Foo.Base", style: .dependency)
        let other = LayoutEdge(sourceId: "Foo", targetId: "Foo.Base", style: .composition)
        let result = DagreLayoutEngine.layout(LayoutGraph(nodes: Self.nodes, edges: [alike, alike, other]))
        #expect(result.edges.map(\.points.isEmpty) == [false, true, false])
    }

    /// Edges each way between a pair were routed apart before; a multigraph keeps them so.
    @Test("edges each way between one pair are each routed")
    func eachWayRouted() {
        let edges = [
            LayoutEdge(sourceId: "Foo", targetId: "Foo.Base", style: .composition),
            LayoutEdge(sourceId: "Foo.Base", targetId: "Foo", style: .dependency),
            LayoutEdge(sourceId: "Foo", targetId: "Foo.Base", style: .inheritance),
        ]
        let result = DagreLayoutEngine.layout(LayoutGraph(nodes: Self.nodes, edges: edges))
        #expect(result.edges.allSatisfy { $0.points.count >= 2 })
    }

    @Test("a name tells apart a style, and a label, from one with a label")
    func edgeNames() {
        let plain = LayoutEdge(sourceId: "Foo", targetId: "Foo.Base", style: .dependency)
        let labelled = LayoutEdge(sourceId: "Foo", targetId: "Foo.Base", label: "", style: .dependency)
        let other = LayoutEdge(sourceId: "Foo", targetId: "Foo.Base", style: .composition)
        let names = [plain, labelled, other].map(DagreLayoutEngine.edgeName(of:))
        #expect(Set(names).count == 3)
    }

    /// The issue's shapes: a nested protocol its parent conforms to, in its own clause or in a
    /// merged extension's, and with and without a module, which lays out in clusters.
    @Test("a nested protocol its parent conforms to keeps both arrows in the SVG",
          arguments: [false, true], [nil, "App"] as [String?])
    func nestedConformance(inExtension: Bool, module: String?) throws {
        let source = inExtension
            ? "struct Foo { public protocol Base {} }\nextension Foo: Foo.Base {}"
            : "struct Foo: Foo.Base { public protocol Base {} }"
        let items = try moduleQualifiedItems([(module: module, source: source)])
        let elements = ElementOptions(showExtensions: inExtension ? .merged : .all)
        let script = DiagramScript(items: items, configuration: Configuration(elements: elements, format: .svg))
        let graph = try #require(script.layoutGraph)
        #expect(graph.fallbackReason == nil)
        let pair = graph.edges.filter { $0.sourceId == "Foo" && $0.targetId == "Foo.Base" }
        #expect(pair.map(\.style.rawValue).sorted() == ["composition", "inheritance"])
        #expect(pair.allSatisfy { $0.points.count >= 2 })
        #expect(script.text.contains("marker-end=\"url(#arrow-composition)\""))
        #expect(script.text.contains("marker-end=\"url(#arrow-inheritance)\""))
    }
}
