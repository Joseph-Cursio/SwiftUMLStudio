import Testing
@testable import SwiftUMLBridgeFramework

/// The grid `DagreLayoutEngine` falls back to when dagre gives no result. It is pure geometry,
/// so these tests call `fallbackLayout` directly on graphs whose nodes are already sized, as
/// `sizeNodes` leaves them before any fallback runs.
@Suite("DagreLayoutEngine — fallback layout")
struct DagreFallbackLayoutTests {

    /// A graph of nodes with the given sizes, named `N0`, `N1`, … in order.
    private func sizedGraph(
        _ sizes: [(width: Double, height: Double)], edges: [LayoutEdge] = []
    ) -> LayoutGraph {
        var graph = LayoutGraph(
            nodes: sizes.indices.map { LayoutNode(id: "N\($0)", label: "N\($0)") },
            edges: edges
        )
        for (idx, size) in sizes.enumerated() {
            graph.nodes[idx].width = size.width
            graph.nodes[idx].height = size.height
        }
        return graph
    }

    /// Each pair of nodes whose boxes overlap, as `"A/B"`. Boxes that only touch do not count.
    private func overlappingPairs(in graph: LayoutGraph) -> [String] {
        var pairs: [String] = []
        for (offset, lhs) in graph.nodes.enumerated() {
            for rhs in graph.nodes.dropFirst(offset + 1)
            where abs(lhs.posX - rhs.posX) < (lhs.width + rhs.width) / 2
                && abs(lhs.posY - rhs.posY) < (lhs.height + rhs.height) / 2 {
                pairs.append("\(lhs.id)/\(rhs.id)")
            }
        }
        return pairs
    }

    // MARK: - Node Placement

    /// The widths `sizeNodes` gave four 44- to 46-character labels in #61's run. On the old
    /// 250-px grid, the first and second boxes of each row overlapped by over 100 px, and every
    /// box crossed the left or right edge of the 500-px canvas.
    @Test("wide nodes neither overlap nor leave the canvas")
    func wideNodes() {
        let graph = sizedGraph([(357.5, 50), (350, 50), (357.5, 50), (365, 50)])
        let laid = DagreLayoutEngine.fallbackLayout(graph)
        #expect(overlappingPairs(in: laid).isEmpty)
        #expect(laid.nodesOutsideCanvas.isEmpty)
    }

    /// `sizeNodes` makes a node with 9 members in one compartment 214 px tall, past the old
    /// 200-px row: a first-row node crossed the top edge and a last-row node the bottom.
    @Test("tall nodes neither overlap nor leave the canvas")
    func tallNodes() {
        let graph = sizedGraph([(100, 214), (100, 50), (100, 50), (100, 320)])
        let laid = DagreLayoutEngine.fallbackLayout(graph)
        #expect(overlappingPairs(in: laid).isEmpty)
        #expect(laid.nodesOutsideCanvas.isEmpty)
    }

    /// Mixed widths and heights on grids of one to twelve nodes, some with a partly filled last row.
    @Test("nodes of mixed sizes neither overlap nor leave the canvas", arguments: 1...12)
    func mixedSizes(count: Int) {
        let sizes = (0..<count).map { idx in
            (width: Double(100 + idx * 137 % 540), height: Double(50 + idx * 89 % 280))
        }
        let laid = DagreLayoutEngine.fallbackLayout(sizedGraph(sizes))
        #expect(overlappingPairs(in: laid).isEmpty, "\(overlappingPairs(in: laid))")
        #expect(laid.nodesOutsideCanvas.isEmpty, "\(laid.nodesOutsideCanvas)")
    }

    @Test("the fallback keeps each node's size")
    func keepsNodeSizes() {
        let sizes: [(width: Double, height: Double)] = [(357.5, 50), (100, 214), (180, 90)]
        let laid = DagreLayoutEngine.fallbackLayout(sizedGraph(sizes))
        #expect(laid.nodes.map(\.width) == sizes.map(\.width))
        #expect(laid.nodes.map(\.height) == sizes.map(\.height))
    }

    // MARK: - Edge Routes

    /// Whether `point` lies on the border of `node`'s box, to within rounding.
    private func isOnBorder(_ point: LayoutPoint, of node: LayoutNode) -> Bool {
        let offsetX = abs(point.posX - node.posX)
        let offsetY = abs(point.posY - node.posY)
        let tolerance = 1e-9
        let inside = offsetX <= node.width / 2 + tolerance && offsetY <= node.height / 2 + tolerance
        let onSide = abs(offsetX - node.width / 2) <= tolerance || abs(offsetY - node.height / 2) <= tolerance
        return inside && onSide
    }

    /// A 3 × 3 grid of boxes of different sizes. From the first node, the edges run to a row
    /// neighbour, a column neighbour, a diagonal one, and a node two cells away; the last edge
    /// runs back up and to the left.
    @Test("each edge runs from its source's border to its target's border")
    func edgesRunBorderToBorder() throws {
        let sizes: [(width: Double, height: Double)] = [
            (357.5, 50), (100, 214), (180, 90), (100, 50), (240, 120), (100, 50), (100, 50), (130, 70), (100, 50)
        ]
        let pairs = [(0, 1), (0, 3), (0, 4), (0, 2), (0, 8), (7, 5)]
        let edges = pairs.map { LayoutEdge(sourceId: "N\($0.0)", targetId: "N\($0.1)", label: "uses") }
        let laid = DagreLayoutEngine.fallbackLayout(sizedGraph(sizes, edges: edges))

        for edge in laid.edges {
            let source = try #require(laid.nodes.first { $0.id == edge.sourceId })
            let target = try #require(laid.nodes.first { $0.id == edge.targetId })
            try #require(edge.points.count == 3, "\(edge.sourceId) → \(edge.targetId)")
            let (start, middle, end) = (edge.points[0], edge.points[1], edge.points[2])
            #expect(isOnBorder(start, of: source), "\(edge.sourceId) → \(edge.targetId) start")
            #expect(isOnBorder(end, of: target), "\(edge.sourceId) → \(edge.targetId) end")
            // The arrow points from the source toward the target, and both renderers put the
            // label at `points[count / 2]`, which is halfway along.
            let towardTarget = (end.posX - start.posX) * (target.posX - source.posX)
                + (end.posY - start.posY) * (target.posY - source.posY)
            #expect(towardTarget > 0)
            #expect(abs(middle.posX - (start.posX + end.posX) / 2) < 1e-9)
            #expect(abs(middle.posY - (start.posY + end.posY) / 2) < 1e-9)
        }
    }

    @Test("a self-loop and an edge to an unknown id get no route")
    func unroutableEdges() {
        let edges = [
            LayoutEdge(sourceId: "N0", targetId: "N0"),
            LayoutEdge(sourceId: "N0", targetId: "Missing"),
            LayoutEdge(sourceId: "N0", targetId: "N1")
        ]
        let laid = DagreLayoutEngine.fallbackLayout(sizedGraph([(100, 50), (100, 50)], edges: edges))
        #expect(laid.edges.map(\.points.count) == [0, 0, 3])
    }

    /// `SVGRenderer.renderEdge` draws nothing for an edge with fewer than two points, so the
    /// fallback used to render as boxes with no relationships.
    @Test("the SVG of a fallback layout draws its edges and their labels")
    func svgDrawsFallbackEdges() {
        let edges = [
            LayoutEdge(sourceId: "N0", targetId: "N1", label: "owns", style: .composition),
            LayoutEdge(sourceId: "N2", targetId: "N0", label: "extends", style: .inheritance)
        ]
        let laid = DagreLayoutEngine.fallbackLayout(sizedGraph([(100, 50), (100, 50), (100, 50)], edges: edges))
        let svg = SVGRenderer.render(laid)
        // Edge paths are the only elements drawn 1.2 px wide; the arrowhead markers are paths too.
        #expect(svg.components(separatedBy: "stroke-width=\"1.2\"").count - 1 == 2)
        #expect(svg.contains(">owns</text>"))
        #expect(svg.contains(">extends</text>"))
    }
}
