import Foundation
import JavaScriptCore
import Testing
@testable import SwiftUMLBridgeFramework

/// Names that reach the JavaScript `DagreLayoutEngine` runs on JavaScriptCore:
/// node ids, edge ends and module names must come back from dagre unchanged.
@Suite("DagreLayoutEngine — names in the layout script")
struct DagreLayoutEngineNameTests {

    // MARK: - Names with JavaScript-Significant Characters

    /// Names that change meaning when pasted between `"` in a JS script:
    /// `Old\Code` loses its backslash (`\C` is an identity escape), `Trail\`
    /// escapes the closing quote, and a raw line terminator ends the literal.
    static let jsSignificantNames = [
        "Old\\Code",
        "Trail\\",
        "Line\nBreak",
        "Carriage\rReturn",
        "Say \"hi\"",
        "Line\u{2028}Separator",
        "Paragraph\u{2029}Separator"
    ]

    /// Asserts `graph` came from dagre, not from `fallbackLayout`: the two
    /// nodes joined by its one edge sit on separate ranks, where the grid
    /// fallback puts both on its first row, and the edge has route points,
    /// which the fallback never sets.
    private func expectDagreLayout(
        _ graph: LayoutGraph, source: String, target: String
    ) throws {
        let sourceNode = try #require(graph.nodes.first { $0.id == source })
        let targetNode = try #require(graph.nodes.first { $0.id == target })
        #expect(sourceNode.posX != 0 || sourceNode.posY != 0)
        #expect(targetNode.posX != 0 || targetNode.posY != 0)
        #expect(sourceNode.posY != targetNode.posY)
        #expect(graph.edges.count == 1)
        #expect(graph.edges.first?.points.count ?? 0 >= 2)
    }

    @Test("jsStringLiteral evaluates back to the original string",
          arguments: jsSignificantNames + ["", "Plain", "a/b</script>", "Tab\tNul\u{0}", "é😀"])
    func jsStringLiteralRoundTrips(value: String) throws {
        let literal = DagreLayoutEngine.jsStringLiteral(value)
        #expect(!literal.contains("\u{2028}") && !literal.contains("\u{2029}"))

        let context = try #require(JSContext())
        let evaluated = try #require(context.evaluateScript(literal))
        #expect(context.exception == nil)
        #expect(evaluated.isString)
        #expect(evaluated.toString() == value)
    }

    @Test("a node named with JS-significant characters gets a dagre position",
          arguments: jsSignificantNames)
    func jsSignificantNodeId(name: String) throws {
        let nodes = [
            LayoutNode(id: name, label: name),
            LayoutNode(id: "Foundation", label: "Foundation")
        ]
        let edges = [LayoutEdge(sourceId: name, targetId: "Foundation", style: .dependency)]
        let result = DagreLayoutEngine.layout(LayoutGraph(nodes: nodes, edges: edges))
        try expectDagreLayout(result, source: name, target: "Foundation")
    }

    @Test("a module named with JS-significant characters keeps its cluster",
          arguments: jsSignificantNames)
    func jsSignificantModuleName(module: String) throws {
        let nodes = [
            LayoutNode(id: "Client", label: "Client", module: module),
            LayoutNode(id: "Session", label: "Session", module: module)
        ]
        let edges = [LayoutEdge(sourceId: "Client", targetId: "Session", style: .dependency)]
        let result = DagreLayoutEngine.layout(LayoutGraph(nodes: nodes, edges: edges))
        try expectDagreLayout(result, source: "Client", target: "Session")

        let cluster = try #require(result.clusters.first)
        #expect(result.clusters.count == 1)
        #expect(cluster.id == module)
        #expect(cluster.label == module)
        #expect(cluster.width > 0)
        #expect(cluster.height > 0)
    }

    // MARK: - Module Names That Start With a Grapheme Extender

    /// Each starts with a scalar that joins the preceding `:` of `cluster:`
    /// into one `Character`: a combining acute, VS16, a ZWJ, a skin-tone
    /// modifier, and a combining mark with nothing after it.
    static let graphemeExtendingModuleNames = [
        "\u{301}Core",
        "\u{FE0F}Kit",
        "\u{200D}Net",
        "\u{1F3FB}Tools",
        "\u{301}"
    ]

    @Test("a module whose name starts with a grapheme extender keeps its first scalar",
          arguments: graphemeExtendingModuleNames)
    func graphemeExtendingModuleName(module: String) throws {
        let nodes = [
            LayoutNode(id: "Client", label: "Client", module: module),
            LayoutNode(id: "Session", label: "Session", module: module)
        ]
        let edges = [LayoutEdge(sourceId: "Client", targetId: "Session", style: .dependency)]
        let result = DagreLayoutEngine.layout(LayoutGraph(nodes: nodes, edges: edges))
        try expectDagreLayout(result, source: "Client", target: "Session")

        let cluster = try #require(result.clusters.first)
        #expect(result.clusters.count == 1)
        #expect(Array(cluster.id.unicodeScalars) == Array(module.unicodeScalars))
        #expect(cluster.label == module)
    }

    // MARK: - Node IDs That Look Like Cluster IDs

    /// Whether `cluster`'s bounding box encloses the node with id `nodeId`.
    private func cluster(
        _ moduleName: String, in graph: LayoutGraph, encloses nodeId: String
    ) throws -> Bool {
        let cluster = try #require(graph.clusters.first { $0.id == moduleName })
        let node = try #require(graph.nodes.first { $0.id == nodeId })
        let clusterRect = CGRect(
            x: cluster.posX - cluster.width / 2, y: cluster.posY - cluster.height / 2,
            width: cluster.width, height: cluster.height
        )
        let nodeRect = CGRect(
            x: node.posX - node.width / 2, y: node.posY - node.height / 2,
            width: node.width, height: node.height
        )
        return clusterRect.contains(nodeRect)
    }

    @Test("a node whose id starts with cluster: is laid out as a node, not a cluster",
          arguments: ["cluster:Core", "cluster:"])
    func clusterPrefixedNodeId(name: String) throws {
        let nodes = [
            LayoutNode(id: name, label: name),
            LayoutNode(id: "Foundation", label: "Foundation")
        ]
        let edges = [LayoutEdge(sourceId: name, targetId: "Foundation", style: .dependency)]
        let result = DagreLayoutEngine.layout(LayoutGraph(nodes: nodes, edges: edges))
        try expectDagreLayout(result, source: name, target: "Foundation")
        #expect(result.clusters.isEmpty)
    }

    @Test("a node named like its own module's cluster stays apart from that cluster")
    func nodeNamedLikeOwnCluster() throws {
        let nodes = [
            LayoutNode(id: "cluster:Core", label: "cluster:Core", module: "Core"),
            LayoutNode(id: "Store", label: "Store", module: "Core")
        ]
        let edges = [LayoutEdge(sourceId: "cluster:Core", targetId: "Store", style: .dependency)]
        let result = DagreLayoutEngine.layout(LayoutGraph(nodes: nodes, edges: edges))
        try expectDagreLayout(result, source: "cluster:Core", target: "Store")

        #expect(result.clusters.map(\.id) == ["Core"])
        #expect(try cluster("Core", in: result, encloses: "cluster:Core"))
        #expect(try cluster("Core", in: result, encloses: "Store"))
    }

    @Test("a node named like another module's cluster stays apart from that cluster")
    func nodeNamedLikeOtherCluster() throws {
        let nodes = [
            LayoutNode(id: "cluster:Net", label: "cluster:Net", module: "App"),
            LayoutNode(id: "Client", label: "Client", module: "Net")
        ]
        let edges = [LayoutEdge(sourceId: "cluster:Net", targetId: "Client", style: .dependency)]
        let result = DagreLayoutEngine.layout(LayoutGraph(nodes: nodes, edges: edges))
        try expectDagreLayout(result, source: "cluster:Net", target: "Client")

        #expect(result.clusters.map(\.id) == ["App", "Net"])
        #expect(try cluster("App", in: result, encloses: "cluster:Net"))
        #expect(try cluster("Net", in: result, encloses: "Client"))
    }
}
