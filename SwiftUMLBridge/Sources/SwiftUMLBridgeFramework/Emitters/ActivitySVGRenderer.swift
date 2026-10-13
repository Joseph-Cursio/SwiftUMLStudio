import Foundation

/// Lays out and renders activity diagrams as SVG without dagre.
///
/// Uses a simple longest-path layering: each node gets a row equal to 1 + max row of any
/// non-back-edge predecessor, where back-edges are those a DFS from the start node finds
/// closing a cycle. Within each row, nodes are spread horizontally in creation order.
/// Back-edges (loop → loopStart) are rendered as dashed curves going upward.
public struct ActivitySVGRenderer: Sendable {

    // MARK: - Layout Constants

    static let topMargin: Double = 40
    static let leftMargin: Double = 40
    static let rightMargin: Double = 40
    static let bottomMargin: Double = 40
    static let rowSpacing: Double = 92
    static let columnSpacing: Double = 200

    static let terminalSize: Double = 28
    static let actionWidth: Double = 170
    static let actionHeight: Double = 44
    static let decisionWidth: Double = 180
    static let decisionHeight: Double = 60
    static let mergeSize: Double = 30
    static let barWidth: Double = 120
    static let barHeight: Double = 8

    // MARK: - Colors

    static let strokeColor = "#333333"
    static let bodyTextColor = "#333333"
    static let actionFill = "#E3F2FD"
    static let asyncActionFill = "#EDE7F6"
    static let decisionFill = "#FFF9C4"
    static let terminalFill = "#333333"
    static let forkJoinFill = "#333333"
    static let mergeFill = "#FFFFFF"

    // MARK: - Public API

    /// Compute a positioned layout for an activity graph.
    public static func computeLayout(from graph: ActivityGraph) -> ActivityLayout {
        let rows = computeRows(graph: graph)
        let columns = computeColumns(graph: graph, rows: rows)

        let maxRow = rows.values.max() ?? 0
        let minCol = columns.values.min() ?? 0
        let maxCol = columns.values.max() ?? 0
        let columnCount = max(1, maxCol - minCol + 1)

        let totalWidth = leftMargin + rightMargin + Double(columnCount) * columnSpacing
        let totalHeight = topMargin + bottomMargin + Double(maxRow + 1) * rowSpacing

        let centerOrigin = leftMargin + Double(-minCol) * columnSpacing + columnSpacing / 2

        var positioned: [PositionedActivityNode] = []
        positioned.reserveCapacity(graph.nodes.count)
        for node in graph.nodes {
            let row = rows[node.id] ?? 0
            let column = columns[node.id] ?? 0
            let (width, height) = nodeSize(kind: node.kind)
            let centerXValue = centerOrigin + Double(column) * columnSpacing
            let centerYValue = topMargin + Double(row) * rowSpacing + height / 2 + 20
            positioned.append(PositionedActivityNode(
                id: node.id, kind: node.kind, label: node.label,
                centerX: centerXValue, centerY: centerYValue,
                width: width, height: height,
                isAsync: node.isAsync, isUnresolved: node.isUnresolved
            ))
        }

        let title = graph.entryType.isEmpty ? "" : "\(graph.entryType).\(graph.entryMethod)"
        return ActivityLayout(
            nodes: positioned, edges: graph.edges,
            title: title, totalWidth: totalWidth, totalHeight: totalHeight
        )
    }

    /// Render an SVG diagram from a pre-computed layout.
    public static func renderFromLayout(_ layout: ActivityLayout) -> String {
        var svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(Int(layout.totalWidth))" \
        height="\(Int(layout.totalHeight))" \
        viewBox="0 0 \(Int(layout.totalWidth)) \(Int(layout.totalHeight))" \
        style="font-family: -apple-system, 'SF Pro Text', 'Helvetica Neue', sans-serif;">
        <defs>
            <marker id="act-arrow" viewBox="0 0 10 10" refX="9" refY="5" \
            markerWidth="8" markerHeight="8" orient="auto-start-reverse">
                <path d="M 0 0 L 10 5 L 0 10 Z" fill="\(strokeColor)"/>
            </marker>
        </defs>

        """

        if !layout.title.isEmpty {
            svg += "<text x=\"\(Int(layout.totalWidth / 2))\" y=\"18\" text-anchor=\"middle\" "
            svg += "font-size=\"14\" font-weight=\"bold\" fill=\"\(bodyTextColor)\">"
            svg += "\(layout.title.xmlEscaped)</text>\n"
        }

        for edge in layout.edges {
            svg += renderEdge(edge: edge, layout: layout)
        }

        for node in layout.nodes {
            svg += renderNode(node)
        }

        svg += "\n</svg>"
        return svg
    }

    /// Convenience — compute layout and render in one call.
    public static func render(graph: ActivityGraph) -> String {
        renderFromLayout(computeLayout(from: graph))
    }

    // MARK: - Layering

    static func computeRows(graph: ActivityGraph) -> [Int: Int] {
        var rows: [Int: Int] = [:]
        guard let start = graph.startNode else {
            for node in graph.nodes { rows[node.id] = 0 }
            return rows
        }

        // Kahn's algorithm over the acyclic forward edges, so a node is placed only after
        // every predecessor has its final row — a join always lands below its longest branch.
        var successors: [Int: [Int]] = [:]
        var inDegree: [Int: Int] = [:]
        for edge in forwardEdges(from: start.id, in: graph.edges) {
            successors[edge.fromId, default: []].append(edge.toId)
            inDegree[edge.toId, default: 0] += 1
        }
        rows[start.id] = 0
        var ready = [start.id]
        while let nodeId = ready.popLast() {
            let nextRow = (rows[nodeId] ?? 0) + 1
            for target in successors[nodeId] ?? [] {
                rows[target] = max(rows[target] ?? 0, nextRow)
                inDegree[target, default: 0] -= 1
                if inDegree[target] == 0 { ready.append(target) }
            }
        }

        for node in graph.nodes where rows[node.id] == nil {
            rows[node.id] = 0
        }
        return rows
    }

    /// The edges reachable from `startId` that are not back-edges, found by an iterative DFS.
    /// An edge whose target is still on the DFS stack (self-loops included) closes a cycle and
    /// is dropped, so what remains is acyclic. Edges among nodes `startId` never reaches are
    /// dropped too — the builder can leave a dead merge or loop wired into reachable nodes.
    static func forwardEdges(from startId: Int, in edges: [ActivityEdge]) -> [ActivityEdge] {
        var outgoing: [Int: [ActivityEdge]] = [:]
        for edge in edges {
            outgoing[edge.fromId, default: []].append(edge)
        }
        var visited: Set<Int> = [startId]
        var onStack: Set<Int> = [startId]
        var stack: [(nodeId: Int, nextEdge: Int)] = [(startId, 0)]
        var forward: [ActivityEdge] = []
        while let top = stack.last {
            let candidates = outgoing[top.nodeId] ?? []
            guard top.nextEdge < candidates.count else {
                stack.removeLast()
                onStack.remove(top.nodeId)
                continue
            }
            stack[stack.count - 1].nextEdge += 1
            let edge = candidates[top.nextEdge]
            if onStack.contains(edge.toId) { continue }
            forward.append(edge)
            if visited.insert(edge.toId).inserted {
                onStack.insert(edge.toId)
                stack.append((edge.toId, 0))
            }
        }
        return forward
    }

    static func computeColumns(graph: ActivityGraph, rows: [Int: Int]) -> [Int: Int] {
        var perRow: [Int: [Int]] = [:]
        for node in graph.nodes {
            perRow[rows[node.id] ?? 0, default: []].append(node.id)
        }
        var columns: [Int: Int] = [:]
        for (_, ids) in perRow {
            let sorted = ids.sorted()
            let count = sorted.count
            for (index, identifier) in sorted.enumerated() {
                columns[identifier] = index - (count - 1) / 2
            }
        }
        return columns
    }

    static func nodeSize(kind: ActivityNodeKind) -> (Double, Double) {
        switch kind {
        case .start, .end: return (terminalSize, terminalSize)
        case .action: return (actionWidth, actionHeight)
        case .decision, .loopStart: return (decisionWidth, decisionHeight)
        case .merge, .loopEnd: return (mergeSize, mergeSize)
        case .fork, .join: return (barWidth, barHeight)
        }
    }

    // MARK: - Helpers

    static func fmt(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
