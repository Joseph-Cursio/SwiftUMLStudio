import Testing
@testable import SwiftUMLBridgeFramework

@Suite("SVGRenderer Tests")
struct SVGRendererTests {

    // MARK: - Empty Graph

    @Test("renders SVG wrapper for empty graph")
    func renderEmptyGraph() {
        let graph = LayoutGraph()
        let svg = SVGRenderer.render(graph)
        #expect(svg.contains("<svg"))
        #expect(svg.contains("</svg>"))
        #expect(svg.contains("xmlns=\"http://www.w3.org/2000/svg\""))
    }

    // MARK: - Single Node

    @Test("renders a node with its label")
    func renderSingleNode() {
        var node = LayoutNode(id: "cls", label: "MyClass", stereotype: "class")
        node.posX = 100
        node.posY = 60
        node.width = 120
        node.height = 50
        let graph = LayoutGraph(nodes: [node])
        let svg = SVGRenderer.render(graph)

        #expect(svg.contains("MyClass"))
        #expect(svg.contains("<rect"))
        #expect(svg.contains("<text"))
    }

    @Test("renders stereotype label in guillemets")
    func renderStereotype() {
        var node = LayoutNode(id: "str", label: "Point", stereotype: "struct")
        node.posX = 100
        node.posY = 60
        node.width = 120
        node.height = 50
        let graph = LayoutGraph(nodes: [node])
        let svg = SVGRenderer.render(graph)

        // Guillemets are XML entities
        #expect(svg.contains("&#x00AB;struct&#x00BB;"))
    }

    @Test("uses correct header fill color for each stereotype")
    func renderHeaderColors() {
        let stereotypes = ["class", "struct", "enum", "protocol", "actor", "extension", "macro"]
        let expectedColors = ["#4A90D9", "#7B68EE", "#E8A838", "#50C878", "#E06666", "#999999", "#CC66CC"]

        for (stereotype, color) in zip(stereotypes, expectedColors) {
            var node = LayoutNode(id: stereotype, label: stereotype, stereotype: stereotype)
            node.posX = 100
            node.posY = 60
            node.width = 120
            node.height = 50
            let graph = LayoutGraph(nodes: [node])
            let svg = SVGRenderer.render(graph)
            #expect(svg.contains(color), "Expected color \(color) for \(stereotype)")
        }
    }

    // MARK: - Compartments

    @Test("renders compartment items")
    func renderCompartments() {
        let compartment = NodeCompartment(items: ["name: String", "age: Int"])
        var node = LayoutNode(
            id: "person", label: "Person", stereotype: "struct",
            compartments: [compartment]
        )
        node.posX = 150
        node.posY = 80
        node.width = 160
        node.height = 100
        let graph = LayoutGraph(nodes: [node])
        let svg = SVGRenderer.render(graph)

        #expect(svg.contains("name: String"))
        #expect(svg.contains("age: Int"))
        // Should have separator line
        #expect(svg.contains("<line"))
    }

    // MARK: - Edges

    @Test("renders edge with points as path")
    func renderEdgePath() {
        var node1 = LayoutNode(id: "aaa", label: "A")
        node1.posX = 100; node1.posY = 50; node1.width = 80; node1.height = 40
        var node2 = LayoutNode(id: "bbb", label: "B")
        node2.posX = 100; node2.posY = 150; node2.width = 80; node2.height = 40

        var edge = LayoutEdge(sourceId: "aaa", targetId: "bbb", style: .inheritance)
        edge.points = [
            LayoutPoint(posX: 100, posY: 70),
            LayoutPoint(posX: 100, posY: 130)
        ]

        let graph = LayoutGraph(nodes: [node1, node2], edges: [edge])
        let svg = SVGRenderer.render(graph)

        #expect(svg.contains("<path"))
        #expect(svg.contains("arrow-inheritance"))
    }

    @Test("does not render edge with fewer than 2 points")
    func renderEdgeInsufficientPoints() {
        var node1 = LayoutNode(id: "aaa", label: "A")
        node1.posX = 100; node1.posY = 50; node1.width = 80; node1.height = 40

        var edge = LayoutEdge(sourceId: "aaa", targetId: "bbb")
        edge.points = [LayoutPoint(posX: 100, posY: 70)] // Only 1 point

        let graphWithEdge = LayoutGraph(nodes: [node1], edges: [edge])
        let svgWithEdge = SVGRenderer.render(graphWithEdge)

        let graphNoEdge = LayoutGraph(nodes: [node1], edges: [])
        let svgNoEdge = SVGRenderer.render(graphNoEdge)

        // An edge with insufficient points should not add any extra path elements
        let pathCountWith = svgWithEdge.components(separatedBy: "<path").count
        let pathCountWithout = svgNoEdge.components(separatedBy: "<path").count
        #expect(pathCountWith == pathCountWithout)
    }

    @Test("renders dashed line for realization edge")
    func renderRealizationEdge() {
        var edge = LayoutEdge(sourceId: "aaa", targetId: "bbb", style: .realization)
        edge.points = [
            LayoutPoint(posX: 50, posY: 50),
            LayoutPoint(posX: 150, posY: 50)
        ]

        var node1 = LayoutNode(id: "aaa", label: "A")
        node1.posX = 50; node1.posY = 50; node1.width = 60; node1.height = 40
        var node2 = LayoutNode(id: "bbb", label: "B")
        node2.posX = 150; node2.posY = 50; node2.width = 60; node2.height = 40

        let graph = LayoutGraph(nodes: [node1, node2], edges: [edge])
        let svg = SVGRenderer.render(graph)

        #expect(svg.contains("stroke-dasharray"))
        #expect(svg.contains("arrow-realization"))
    }

    @Test("renders dashed line for dependency edge")
    func renderDependencyEdge() {
        var edge = LayoutEdge(sourceId: "aaa", targetId: "bbb", style: .dependency)
        edge.points = [
            LayoutPoint(posX: 50, posY: 50),
            LayoutPoint(posX: 150, posY: 50)
        ]

        var node1 = LayoutNode(id: "aaa", label: "A")
        node1.posX = 50; node1.posY = 50; node1.width = 60; node1.height = 40
        var node2 = LayoutNode(id: "bbb", label: "B")
        node2.posX = 150; node2.posY = 50; node2.width = 60; node2.height = 40

        let graph = LayoutGraph(nodes: [node1, node2], edges: [edge])
        let svg = SVGRenderer.render(graph)

        #expect(svg.contains("stroke-dasharray"))
        #expect(svg.contains("arrow-dependency"))
    }

    @Test("renders composition edge with diamond marker")
    func renderCompositionEdge() {
        var edge = LayoutEdge(sourceId: "aaa", targetId: "bbb", style: .composition)
        edge.points = [
            LayoutPoint(posX: 50, posY: 50),
            LayoutPoint(posX: 150, posY: 50)
        ]

        var node1 = LayoutNode(id: "aaa", label: "A")
        node1.posX = 50; node1.posY = 50; node1.width = 60; node1.height = 40
        var node2 = LayoutNode(id: "bbb", label: "B")
        node2.posX = 150; node2.posY = 50; node2.width = 60; node2.height = 40

        let graph = LayoutGraph(nodes: [node1, node2], edges: [edge])
        let svg = SVGRenderer.render(graph)

        #expect(svg.contains("arrow-composition"))
    }

    @Test("association edge has no marker")
    func renderAssociationEdge() {
        var edge = LayoutEdge(sourceId: "aaa", targetId: "bbb", style: .association)
        edge.points = [
            LayoutPoint(posX: 50, posY: 50),
            LayoutPoint(posX: 150, posY: 50)
        ]

        var node1 = LayoutNode(id: "aaa", label: "A")
        node1.posX = 50; node1.posY = 50; node1.width = 60; node1.height = 40
        var node2 = LayoutNode(id: "bbb", label: "B")
        node2.posX = 150; node2.posY = 50; node2.width = 60; node2.height = 40

        let graph = LayoutGraph(nodes: [node1, node2], edges: [edge])
        let svg = SVGRenderer.render(graph)

        #expect(svg.contains("<path"))
        #expect(svg.contains("marker-end") == false)
    }

    // MARK: - Edge Labels

    @Test("renders edge label when present")
    func renderEdgeLabel() {
        var edge = LayoutEdge(
            sourceId: "aaa", targetId: "bbb", label: "conforms", style: .realization
        )
        edge.points = [
            LayoutPoint(posX: 50, posY: 50),
            LayoutPoint(posX: 100, posY: 75),
            LayoutPoint(posX: 150, posY: 100)
        ]

        var node1 = LayoutNode(id: "aaa", label: "A")
        node1.posX = 50; node1.posY = 50; node1.width = 60; node1.height = 40
        var node2 = LayoutNode(id: "bbb", label: "B")
        node2.posX = 150; node2.posY = 100; node2.width = 60; node2.height = 40

        let graph = LayoutGraph(nodes: [node1, node2], edges: [edge])
        let svg = SVGRenderer.render(graph)

        #expect(svg.contains("conforms"))
    }

    // MARK: - XML Escaping

    @Test("escapes special XML characters in labels")
    func xmlEscaping() {
        var node = LayoutNode(id: "gen", label: "Array<Int>", stereotype: "class")
        node.posX = 100; node.posY = 60; node.width = 120; node.height = 50
        let graph = LayoutGraph(nodes: [node])
        let svg = SVGRenderer.render(graph)

        #expect(svg.contains("Array&lt;Int&gt;"))
        #expect(svg.contains("Array<Int>") == false)
    }

    // MARK: - Arrow Markers

    @Test("SVG contains arrow marker definitions")
    func containsArrowMarkers() {
        let graph = LayoutGraph()
        let svg = SVGRenderer.render(graph)

        #expect(svg.contains("<defs>"))
        #expect(svg.contains("arrow-inheritance"))
        #expect(svg.contains("arrow-realization"))
        #expect(svg.contains("arrow-dependency"))
        #expect(svg.contains("arrow-composition"))
    }

    // MARK: - Module Clusters

    @Test("renders a module cluster box with its label")
    func renderCluster() {
        var cluster = LayoutCluster(id: "Networking", label: "Networking")
        cluster.posX = 200; cluster.posY = 150; cluster.width = 300; cluster.height = 220
        var graph = LayoutGraph()
        graph.clusters = [cluster]
        let svg = SVGRenderer.render(graph)

        #expect(svg.contains("<!-- module: Networking -->"))
        #expect(svg.contains(">Networking</text>"))
        // Dashed, tinted rectangle.
        #expect(svg.contains("stroke-dasharray=\"6,3\""))
        #expect(svg.contains("fill-opacity=\"0.10\""))
    }

    @Test("cluster color is deterministic per module name")
    func clusterColorIsDeterministic() {
        var cluster = LayoutCluster(id: "Core", label: "Core")
        cluster.width = 100; cluster.height = 100
        var graph = LayoutGraph()
        graph.clusters = [cluster]

        let first = SVGRenderer.render(graph)
        let second = SVGRenderer.render(graph)
        #expect(first == second)
        #expect(first.contains("hsl("))
    }

    @Test("graph without clusters renders no module comment")
    func noClustersNoModuleComment() {
        var node = LayoutNode(id: "cls", label: "Solo", stereotype: "class")
        node.posX = 100; node.posY = 60; node.width = 120; node.height = 50
        let svg = SVGRenderer.render(LayoutGraph(nodes: [node]))
        #expect(svg.contains("<!-- module:") == false)
    }

    // MARK: - Dimensions

    @Test("SVG dimensions include margin")
    func svgDimensionsIncludeMargin() {
        var graph = LayoutGraph()
        graph.width = 400
        graph.height = 300
        let svg = SVGRenderer.render(graph)

        // Margin is 20 on each side, so total = 440 x 340
        #expect(svg.contains("width=\"440\""))
        #expect(svg.contains("height=\"340\""))
    }
}
