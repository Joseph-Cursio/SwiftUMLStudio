import Foundation

// MARK: - Mermaid (flowchart flavor)

extension ActivityScript {
    static func buildMermaidText(from graph: ActivityGraph) -> String {
        var lines: [String] = ["flowchart TD"]
        if !graph.entryType.isEmpty {
            lines.append("%% title: \(graph.entryType).\(graph.entryMethod)")
        }

        if graph.nodes.isEmpty {
            return lines.joined(separator: "\n")
        }

        for node in graph.nodes {
            lines.append(contentsOf: mermaidNodeLines(node))
        }

        lines.append("classDef forkJoin fill:#333,stroke:#333,color:#fff,stroke-width:2px;")

        for edge in graph.edges {
            lines.append(mermaidEdgeLine(edge))
        }

        return lines.joined(separator: "\n")
    }

    /// Emit the Mermaid shape lines for one activity node.
    static func mermaidNodeLines(_ node: ActivityNode) -> [String] {
        let identifier = "N\(node.id)"
        let label = mermaidEscape(node.label)
        switch node.kind {
        case .start:
            return ["\(identifier)((\"start\"))"]

        case .end:
            return ["\(identifier)(((\"end\")))"]

        case .action:
            let prefix = node.isAsync ? mermaidEscape("await ") : ""
            return ["\(identifier)[\"\(prefix)\(label)\"]"]

        case .decision, .loopStart:
            return ["\(identifier){\"\(label)\"}"]

        case .merge, .loopEnd:
            return ["\(identifier){\" \"}"]

        case .fork, .join:
            return [
                "\(identifier):::forkJoin",
                "\(identifier)[\" \"]",
            ]
        }
    }

    static func mermaidEdgeLine(_ edge: ActivityEdge) -> String {
        let from = "N\(edge.fromId)"
        let to = "N\(edge.toId)"
        if let label = edge.label, !label.isEmpty {
            // Quoted, since Mermaid rejects a `(` or `[` in a bare edge label and with it the whole
            // diagram: `-->|.failure(let error)|` and `-->|#if os(iOS)|` did not parse.
            return "\(from) -->|\"\(mermaidEscape(label))\"| \(to)"
        }
        return "\(from) --> \(to)"
    }
}
