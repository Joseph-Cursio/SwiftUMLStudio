import Foundation

// MARK: - Mermaid

extension DepsScript {
    static func buildMermaidText(model: DependencyGraphModel, cycleNodes: Set<String>) -> String {
        var lines: [String] = ["graph TD"]

        // Collect unique node names for declarations
        var seenNodes = Set<String>()
        for edge in model.edges {
            seenNodes.insert(edge.from)
            seenNodes.insert(edge.to)
        }

        let stereotypes = Self.nodeStereotypes(model: model)

        // One identifier per node, claimed in sorted order so the output is stable.
        var ids = DiagramIdentifiers(sanitize: mermaidId)
        for node in seenNodes.sorted() {
            _ = ids.id(for: node)
        }

        // Declare nodes with quoted labels. In package mode the label
        // gets an extra line carrying the stereotype («library» / module
        // name) — flowchart syntax doesn't accept `<<>>` directly, so we
        // use guillemets which render cleanly as a UML stereotype.
        for node in seenNodes.sorted() {
            let safeId = ids.id(for: node)
            let label: String
            if let stereotype = stereotypes[node] {
                label = "\(node)<br/>«\(stereotype)»"
            } else {
                label = node
            }
            lines.append("    \(safeId)[\"\(label)\"]")
        }

        if !seenNodes.isEmpty {
            lines.append("")
        }

        // Emit edge lines
        for edge in model.edges {
            let fromId = ids.id(for: edge.from)
            let toId = ids.id(for: edge.to)
            lines.append("    \(fromId) --> \(toId)")
        }

        // Annotate cycle nodes with red fill
        if !cycleNodes.isEmpty {
            lines.append("")
            for node in cycleNodes.sorted() {
                let safeId = ids.id(for: node)
                lines.append("    style \(safeId) fill:#ffcccc,stroke:#cc0000")
            }
        }

        return lines.joined(separator: "\n")
    }
}
