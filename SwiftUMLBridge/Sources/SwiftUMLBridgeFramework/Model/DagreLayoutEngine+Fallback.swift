import Foundation

// MARK: - Fallback

/// The grid layout for when dagre gives none, kept apart so the engine stays a readable size.
extension DagreLayoutEngine {
    /// Grid layout for when dagre gives no result: JavaScriptCore or
    /// `graphre.js` cannot be loaded, the layout script throws or does not
    /// parse, or what it returns is not a JSON object.
    ///
    /// Every cell is the size of the largest node plus dagre's node spacing,
    /// so no two boxes overlap, and the grid sits inside dagre's margin, so
    /// every box is on the canvas. A fixed 250 × 200 cell let wide or tall
    /// nodes overlap their neighbours and run off the canvas (#61). Edges are
    /// routed straight (see `routeStraightEdges`); no module clusters are set.
    /// `reason` goes in `fallbackReason`, so callers can say the layout failed.
    static func fallbackLayout(_ graph: LayoutGraph, because reason: String) -> LayoutGraph {
        var result = graph
        result.fallbackReason = reason
        let count = graph.nodes.count
        let columns = max(Int(ceil(sqrt(Double(count)))), 1)
        let rows = (count + columns - 1) / columns
        let cellWidth = (graph.nodes.map(\.width).max() ?? 0) + nodeSpacing
        let cellHeight = (graph.nodes.map(\.height).max() ?? 0) + nodeSpacing

        for idx in result.nodes.indices {
            let col = idx % columns
            let row = idx / columns
            result.nodes[idx].posX = canvasMargin + (Double(col) + 0.5) * cellWidth
            result.nodes[idx].posY = canvasMargin + (Double(row) + 0.5) * cellHeight
        }

        result.width = 2 * canvasMargin + Double(columns) * cellWidth
        result.height = 2 * canvasMargin + Double(rows) * cellHeight
        routeStraightEdges(&result)
        return result
    }

    /// Routes each edge in a straight line between the facing borders of its
    /// two boxes, through a midpoint where both renderers put the edge's label.
    /// Both renderers skip an edge with fewer than two points, so without this
    /// the fallback drew no relationships at all. The ends sit on the borders,
    /// not at the centres, because nodes are drawn over edges and would hide
    /// the arrowhead. A line between boxes that are not neighbours can pass
    /// under a box between them. A self-loop, or an edge to an id with no
    /// node, is left without points.
    private static func routeStraightEdges(_ graph: inout LayoutGraph) {
        var boxes: [String: LayoutNode] = [:]
        for node in graph.nodes where boxes[node.id] == nil {
            boxes[node.id] = node
        }
        for idx in graph.edges.indices {
            let edge = graph.edges[idx]
            guard edge.sourceId != edge.targetId,
                  let source = boxes[edge.sourceId],
                  let target = boxes[edge.targetId] else {
                graph.edges[idx].points = []
                continue
            }
            let start = borderPoint(of: source, toward: target)
            let end = borderPoint(of: target, toward: source)
            let middle = LayoutPoint(posX: (start.posX + end.posX) / 2, posY: (start.posY + end.posY) / 2)
            graph.edges[idx].points = [start, middle, end]
        }
    }

    /// Where the line from `node`'s centre toward `other`'s centre crosses
    /// `node`'s border: through whichever side it reaches first.
    private static func borderPoint(of node: LayoutNode, toward other: LayoutNode) -> LayoutPoint {
        let deltaX = other.posX - node.posX
        let deltaY = other.posY - node.posY
        let scaleX = deltaX == 0 ? 1 : min(node.width / 2 / abs(deltaX), 1)
        let scaleY = deltaY == 0 ? 1 : min(node.height / 2 / abs(deltaY), 1)
        let scale = min(scaleX, scaleY)
        return LayoutPoint(posX: node.posX + deltaX * scale, posY: node.posY + deltaY * scale)
    }
}
