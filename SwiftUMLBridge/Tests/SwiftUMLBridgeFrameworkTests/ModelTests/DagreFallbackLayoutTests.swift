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
}
