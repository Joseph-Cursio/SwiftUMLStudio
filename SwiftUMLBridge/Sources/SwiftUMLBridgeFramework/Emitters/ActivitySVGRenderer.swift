import Foundation

/// Lays out and renders activity diagrams as SVG without dagre.
///
/// Uses a simple longest-path layering: each node gets a row equal to 1 + max row of any
/// non-back-edge predecessor. Within each row, nodes are spread horizontally in creation
/// order. Back-edges (loop → loopStart) are rendered as dashed curves going upward.
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
            svg += "\(escapeXML(layout.title))</text>\n"
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
        rows[start.id] = 0

        let iterationCap = graph.nodes.count * max(1, graph.edges.count) + 10
        var iterations = 0
        var changed = true
        while changed && iterations < iterationCap {
            changed = false
            iterations += 1
            for edge in graph.edges {
                guard edge.toId != edge.fromId else { continue }
                guard let fromRow = rows[edge.fromId] else { continue }
                if let toRow = rows[edge.toId], toRow <= fromRow { continue }
                let newRow = fromRow + 1
                if let existing = rows[edge.toId] {
                    if newRow > existing {
                        rows[edge.toId] = newRow
                        changed = true
                    }
                } else {
                    rows[edge.toId] = newRow
                    changed = true
                }
            }
        }

        for node in graph.nodes where rows[node.id] == nil {
            rows[node.id] = 0
        }
        return rows
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

    static func escapeXML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func fmt(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
