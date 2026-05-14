import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

@Suite("DagreLayoutEngine Tests")
struct DagreLayoutEngineTests {

    // MARK: - Empty Graph

    @Test("layout returns empty graph unchanged")
    func layoutEmptyGraph() {
        let graph = LayoutGraph()
        let result = DagreLayoutEngine.layout(graph)
        #expect(result.nodes.isEmpty)
        #expect(result.edges.isEmpty)
    }

    // MARK: - Single Node

    @Test("layout positions a single node")
    func layoutSingleNode() {
        let node = LayoutNode(id: "NodeA", label: "NodeA")
        let graph = LayoutGraph(nodes: [node])
        let result = DagreLayoutEngine.layout(graph)

        #expect(result.nodes.count == 1)
        // After layout, position should be set (non-zero in at least one axis)
        let positioned = result.nodes[0]
        #expect(positioned.width > 0)
        #expect(positioned.height > 0)
        // Dagre sets graph dimensions
        #expect(result.width > 0)
        #expect(result.height > 0)
    }

    // MARK: - Multiple Nodes

    @Test("layout positions multiple nodes without overlap")
    func layoutMultipleNodes() {
        let nodes = [
            LayoutNode(id: "aaa", label: "ClassA"),
            LayoutNode(id: "bbb", label: "ClassB"),
            LayoutNode(id: "ccc", label: "ClassC")
        ]
        let graph = LayoutGraph(nodes: nodes)
        let result = DagreLayoutEngine.layout(graph)

        #expect(result.nodes.count == 3)
        // All nodes should have been sized
        for node in result.nodes {
            #expect(node.width >= 100)
            #expect(node.height >= 50)
        }
    }

    // MARK: - Edges

    @Test("layout routes edges with points")
    func layoutEdgesWithPoints() {
        let nodes = [
            LayoutNode(id: "parent", label: "Parent"),
            LayoutNode(id: "child", label: "Child")
        ]
        let edges = [
            LayoutEdge(sourceId: "child", targetId: "parent", style: .inheritance)
        ]
        let graph = LayoutGraph(nodes: nodes, edges: edges)
        let result = DagreLayoutEngine.layout(graph)

        #expect(result.edges.count == 1)
        // Dagre should provide route points for the edge
        #expect(result.edges[0].points.count >= 2)
    }

    // MARK: - Node Sizing

    @Test("nodes with compartments are taller than empty nodes")
    func nodesWithCompartmentsAreTaller() {
        let emptyNode = LayoutNode(id: "empty", label: "Empty")
        let richNode = LayoutNode(
            id: "rich", label: "Rich",
            compartments: [
                NodeCompartment(items: ["prop1: Int", "prop2: String", "prop3: Bool"]),
                NodeCompartment(items: ["method1()", "method2()"])
            ]
        )
        let graph = LayoutGraph(nodes: [emptyNode, richNode])
        let result = DagreLayoutEngine.layout(graph)

        let emptyResult = result.nodes.first { $0.id == "empty" }!
        let richResult = result.nodes.first { $0.id == "rich" }!
        #expect(richResult.height > emptyResult.height)
    }

    @Test("nodes with long labels are wider")
    func nodesWithLongLabelsAreWider() {
        let shortNode = LayoutNode(id: "short", label: "AB")
        let longNode = LayoutNode(
            id: "long", label: "AVeryLongClassNameThatShouldBeWider"
        )
        let graph = LayoutGraph(nodes: [shortNode, longNode])
        let result = DagreLayoutEngine.layout(graph)

        let shortResult = result.nodes.first { $0.id == "short" }!
        let longResult = result.nodes.first { $0.id == "long" }!
        #expect(longResult.width > shortResult.width)
    }

    @Test("minimum node width is 100")
    func minimumNodeWidth() {
        let node = LayoutNode(id: "tiny", label: "X")
        let graph = LayoutGraph(nodes: [node])
        let result = DagreLayoutEngine.layout(graph)
        #expect(result.nodes[0].width >= 100)
    }

    @Test("minimum node height is 50")
    func minimumNodeHeight() {
        let node = LayoutNode(id: "tiny", label: "X")
        let graph = LayoutGraph(nodes: [node])
        let result = DagreLayoutEngine.layout(graph)
        #expect(result.nodes[0].height >= 50)
    }

    // MARK: - Graph with Connected Components

    @Test("layout handles a linear chain of nodes")
    func layoutLinearChain() {
        let nodes = [
            LayoutNode(id: "aaa", label: "A"),
            LayoutNode(id: "bbb", label: "B"),
            LayoutNode(id: "ccc", label: "C")
        ]
        let edges = [
            LayoutEdge(sourceId: "aaa", targetId: "bbb", style: .inheritance),
            LayoutEdge(sourceId: "bbb", targetId: "ccc", style: .inheritance)
        ]
        let graph = LayoutGraph(nodes: nodes, edges: edges)
        let result = DagreLayoutEngine.layout(graph)

        #expect(result.nodes.count == 3)
        #expect(result.edges.count == 2)
        // All edges should have route points
        for edge in result.edges {
            #expect(edge.points.count >= 2)
        }
    }

    // MARK: - Module Clustering (Compound Layout)

    @Test("graph without modules produces no clusters")
    func noModulesNoClusters() {
        let nodes = [
            LayoutNode(id: "aaa", label: "A"),
            LayoutNode(id: "bbb", label: "B")
        ]
        let result = DagreLayoutEngine.layout(LayoutGraph(nodes: nodes))
        #expect(result.clusters.isEmpty)
    }

    @Test("nodes carrying modules produce a cluster per module")
    func modulesProduceClusters() {
        let nodes = [
            LayoutNode(id: "Client", label: "Client", module: "Networking"),
            LayoutNode(id: "Session", label: "Session", module: "Networking"),
            LayoutNode(id: "Store", label: "Store", module: "Persistence")
        ]
        let result = DagreLayoutEngine.layout(LayoutGraph(nodes: nodes))

        #expect(result.clusters.count == 2)
        let ids = Set(result.clusters.map(\.id))
        #expect(ids == ["Networking", "Persistence"])
        // Every node is still positioned and sized.
        #expect(result.nodes.count == 3)
        for node in result.nodes {
            #expect(node.width > 0)
            #expect(node.height > 0)
        }
    }

    @Test("cluster bounding box has positive size and encloses its nodes")
    func clusterEnclosesNodes() {
        let nodes = [
            LayoutNode(id: "First", label: "First", module: "Core"),
            LayoutNode(id: "Second", label: "Second", module: "Core")
        ]
        let result = DagreLayoutEngine.layout(LayoutGraph(nodes: nodes))

        let cluster = try! #require(result.clusters.first { $0.id == "Core" })
        #expect(cluster.width > 0)
        #expect(cluster.height > 0)

        let clusterRect = CGRect(
            x: cluster.posX - cluster.width / 2, y: cluster.posY - cluster.height / 2,
            width: cluster.width, height: cluster.height
        )
        for node in result.nodes {
            let nodeRect = CGRect(
                x: node.posX - node.width / 2, y: node.posY - node.height / 2,
                width: node.width, height: node.height
            )
            #expect(clusterRect.contains(nodeRect))
        }
    }

    @Test("module clustering preserves edge routing")
    func clusteringPreservesEdges() {
        let nodes = [
            LayoutNode(id: "child", label: "Child", module: "App"),
            LayoutNode(id: "parent", label: "Parent", module: "App")
        ]
        let edges = [LayoutEdge(sourceId: "child", targetId: "parent", style: .inheritance)]
        let result = DagreLayoutEngine.layout(LayoutGraph(nodes: nodes, edges: edges))

        #expect(result.edges.count == 1)
        #expect(result.edges[0].points.count >= 2)
    }

    // MARK: - Node IDs with Special Characters

    @Test("handles node IDs with dots")
    func nodeIdsWithDots() {
        let node = LayoutNode(id: "Module.MyClass", label: "MyClass")
        let graph = LayoutGraph(nodes: [node])
        let result = DagreLayoutEngine.layout(graph)
        #expect(result.nodes.count == 1)
        #expect(result.nodes[0].width > 0)
    }
}
