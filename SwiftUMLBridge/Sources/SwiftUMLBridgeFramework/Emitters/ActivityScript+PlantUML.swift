// MARK: - PlantUML (state-diagram flavor)

extension ActivityScript {
    static func buildPlantUMLText(from graph: ActivityGraph) -> String {
        var lines: [String] = ["@startuml"]
        if !graph.entryType.isEmpty {
            lines.append("title \(graph.entryType).\(graph.entryMethod)")
        }

        if graph.nodes.isEmpty {
            lines.append("@enduml")
            return lines.joined(separator: "\n")
        }

        for node in graph.nodes {
            if let line = plantUMLNodeLine(node) {
                lines.append(line)
            }
        }

        lines.append("")

        for edge in graph.edges {
            lines.append(plantUMLEdgeLine(edge, graph: graph))
        }

        lines.append("@enduml")
        return lines.joined(separator: "\n")
    }

    /// Emit the PlantUML `state` declaration line for one node, or `nil` when
    /// the node is represented by `[*]` in transitions (start/end pseudo-states).
    static func plantUMLNodeLine(_ node: ActivityNode) -> String? {
        switch node.kind {
        case .start, .end:
            return nil

        case .action:
            let prefix = node.isAsync ? "await " : ""
            return "state \"\(plantUMLEscape(prefix + node.label))\" as N\(node.id)"

        case .decision, .loopStart:
            return "state \"\(plantUMLEscape(node.label))\" as N\(node.id) <<choice>>"

        case .merge, .loopEnd:
            return "state \" \" as N\(node.id) <<choice>>"

        case .fork:
            return "state \" \" as N\(node.id) <<fork>>"

        case .join:
            return "state \" \" as N\(node.id) <<join>>"
        }
    }

    static func plantUMLEdgeLine(_ edge: ActivityEdge, graph: ActivityGraph) -> String {
        let from = plantUMLRef(id: edge.fromId, graph: graph)
        let to = plantUMLRef(id: edge.toId, graph: graph)
        if let label = edge.label, !label.isEmpty {
            return "\(from) --> \(to) : \(plantUMLEscape(label))"
        }
        return "\(from) --> \(to)"
    }

    static func plantUMLRef(id: Int, graph: ActivityGraph) -> String {
        if let node = graph.node(withId: id), node.kind == .start || node.kind == .end {
            return "[*]"
        }
        return "N\(id)"
    }
}
