import Testing
@testable import SwiftUMLBridgeFramework

@Suite("LayoutGraph Tests")
struct LayoutGraphTests {

    // MARK: - LayoutGraph

    @Test("initializes with default empty nodes and edges")
    func defaultInit() {
        let graph = LayoutGraph()
        #expect(graph.nodes.isEmpty)
        #expect(graph.edges.isEmpty)
        #expect(graph.width == 0)
        #expect(graph.height == 0)
    }

    @Test("initializes with provided nodes and edges")
    func initWithNodesAndEdges() {
        let node = LayoutNode(id: "NodeA", label: "NodeA")
        let edge = LayoutEdge(sourceId: "NodeA", targetId: "NodeB")
        let graph = LayoutGraph(nodes: [node], edges: [edge])

        #expect(graph.nodes.count == 1)
        #expect(graph.edges.count == 1)
        #expect(graph.nodes[0].id == "NodeA")
        #expect(graph.edges[0].sourceId == "NodeA")
    }

    @Test("width and height are mutable")
    func mutableDimensions() {
        var graph = LayoutGraph()
        graph.width = 500
        graph.height = 300
        #expect(graph.width == 500)
        #expect(graph.height == 300)
    }

    @Test("clusters default to empty")
    func defaultClusters() {
        let graph = LayoutGraph(nodes: [LayoutNode(id: "a", label: "A")])
        #expect(graph.clusters.isEmpty)
    }

    @Test("clusters are mutable")
    func mutableClusters() {
        var graph = LayoutGraph()
        graph.clusters = [LayoutCluster(id: "Networking", label: "Networking")]
        #expect(graph.clusters.count == 1)
        #expect(graph.clusters[0].id == "Networking")
    }

    // MARK: - LayoutCluster

    @Test("cluster initializes with id and label and zeroed geometry")
    func clusterDefaults() {
        let cluster = LayoutCluster(id: "Core", label: "Core")
        #expect(cluster.id == "Core")
        #expect(cluster.label == "Core")
        #expect(cluster.posX == 0)
        #expect(cluster.posY == 0)
        #expect(cluster.width == 0)
        #expect(cluster.height == 0)
    }

    @Test("cluster position and size are mutable")
    func clusterMutableGeometry() {
        var cluster = LayoutCluster(id: "UI", label: "UI")
        cluster.posX = 250
        cluster.posY = 120
        cluster.width = 400
        cluster.height = 300
        #expect(cluster.posX == 250)
        #expect(cluster.posY == 120)
        #expect(cluster.width == 400)
        #expect(cluster.height == 300)
    }

    @Test("cluster conforms to Identifiable via its module id")
    func clusterIdentifiable() {
        let clusterA = LayoutCluster(id: "ModuleA", label: "ModuleA")
        let clusterB = LayoutCluster(id: "ModuleB", label: "ModuleB")
        #expect(clusterA.id != clusterB.id)
    }

    // MARK: - LayoutNode

    @Test("node initializes with required fields and defaults")
    func nodeDefaults() {
        let node = LayoutNode(id: "myNode", label: "MyClass")
        #expect(node.id == "myNode")
        #expect(node.label == "MyClass")
        #expect(node.stereotype == nil)
        #expect(node.compartments.isEmpty)
        #expect(node.posX == 0)
        #expect(node.posY == 0)
        #expect(node.width == 0)
        #expect(node.height == 0)
    }

    @Test("node initializes with all parameters")
    func nodeFullInit() {
        let compartment = NodeCompartment(title: "Properties", items: ["name: String"])
        let node = LayoutNode(
            id: "cls",
            label: "MyClass",
            stereotype: "class",
            compartments: [compartment]
        )
        #expect(node.stereotype == "class")
        #expect(node.compartments.count == 1)
        #expect(node.compartments[0].items == ["name: String"])
    }

    @Test("node conforms to Identifiable")
    func nodeIdentifiable() {
        let nodeA = LayoutNode(id: "aaa", label: "A")
        let nodeB = LayoutNode(id: "bbb", label: "B")
        #expect(nodeA.id != nodeB.id)
    }

    @Test("node position and size are mutable")
    func nodeMutablePosition() {
        var node = LayoutNode(id: "nnn", label: "N")
        node.posX = 100
        node.posY = 200
        node.width = 150
        node.height = 80
        #expect(node.posX == 100)
        #expect(node.posY == 200)
        #expect(node.width == 150)
        #expect(node.height == 80)
    }

    // MARK: - NodeCompartment

    @Test("compartment initializes with title and items")
    func compartmentInit() {
        let comp = NodeCompartment(title: "Methods", items: ["foo()", "bar()"])
        #expect(comp.title == "Methods")
        #expect(comp.items.count == 2)
    }

    @Test("compartment title defaults to nil")
    func compartmentNilTitle() {
        let comp = NodeCompartment(items: ["value: Int"])
        #expect(comp.title == nil)
        #expect(comp.items == ["value: Int"])
    }

    @Test("compartment with empty items")
    func compartmentEmptyItems() {
        let comp = NodeCompartment(items: [])
        #expect(comp.items.isEmpty)
    }

    // MARK: - LayoutEdge

    @Test("edge initializes with defaults")
    func edgeDefaults() {
        let edge = LayoutEdge(sourceId: "src", targetId: "tgt")
        #expect(edge.sourceId == "src")
        #expect(edge.targetId == "tgt")
        #expect(edge.label == nil)
        #expect(edge.style == .association)
        #expect(edge.points.isEmpty)
    }

    @Test("edge initializes with all parameters")
    func edgeFullInit() {
        let edge = LayoutEdge(
            sourceId: "src",
            targetId: "tgt",
            label: "extends",
            style: .inheritance
        )
        #expect(edge.label == "extends")
        #expect(edge.style == .inheritance)
    }

    @Test("edge points are mutable")
    func edgeMutablePoints() {
        var edge = LayoutEdge(sourceId: "aaa", targetId: "bbb")
        edge.points = [
            LayoutPoint(posX: 0, posY: 0),
            LayoutPoint(posX: 100, posY: 100)
        ]
        #expect(edge.points.count == 2)
        #expect(edge.points[1].posX == 100)
    }

    // MARK: - EdgeStyle

    @Test("all edge styles have raw values")
    func edgeStyleRawValues() {
        #expect(EdgeStyle.inheritance.rawValue == "inheritance")
        #expect(EdgeStyle.realization.rawValue == "realization")
        #expect(EdgeStyle.dependency.rawValue == "dependency")
        #expect(EdgeStyle.association.rawValue == "association")
        #expect(EdgeStyle.composition.rawValue == "composition")
    }

    // MARK: - LayoutPoint

    @Test("point stores coordinates")
    func pointInit() {
        let point = LayoutPoint(posX: 42.5, posY: 99.9)
        #expect(point.posX == 42.5)
        #expect(point.posY == 99.9)
    }

    @Test("point handles negative coordinates")
    func pointNegative() {
        let point = LayoutPoint(posX: -10, posY: -20)
        #expect(point.posX == -10)
        #expect(point.posY == -20)
    }

    @Test("point handles zero coordinates")
    func pointZero() {
        let point = LayoutPoint(posX: 0, posY: 0)
        #expect(point.posX == 0)
        #expect(point.posY == 0)
    }
}
