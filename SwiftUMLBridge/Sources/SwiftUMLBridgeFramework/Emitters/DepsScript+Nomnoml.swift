// MARK: - Nomnoml

extension DepsScript {
    static func buildNomnomlText(model: DependencyGraphModel, cycleNodes: Set<String>) -> String {
        // Output-building — these are nomnoml directive lines joined into a diagram script, not a
        // registry; Parallel List Drift pairs them with another emitter's line run. Not drift.
        // swiftprojectlint:disable:next parallel-list-drift
        var lines: [String] = [
            "#direction: down",
            "#fontSize: 12",
            "#spacing: 60",
            "#edges: rounded",
        ]

        let stereotypes = Self.nodeStereotypes(model: model)

        // Declare each cycle node as a `warning` box before any edge names it. nomnoml merges
        // nodes of the same text and keeps the first, so the box must come first and be spelled
        // exactly as the edges spell it, stereotype included (#142).
        if !cycleNodes.isEmpty {
            let sorted = cycleNodes.sorted()
            lines.append("")
            lines.append("// Cyclic nodes: \(sorted.joined(separator: ", "))")
            lines.append("#.warning: fill=#ffcccc stroke=#cc0000")
            for node in sorted {
                lines.append("[<warning> \(nomnomlLabel(node, stereotype: stereotypes[node]))]")
            }
            lines.append("")
        }

        // Emit edges: [From] arrow [To]. Nomnoml identifies nodes by
        // literal label, so when we have SPM provenance we inline the
        // stereotype into both endpoints rather than declaring nodes
        // separately.
        for edge in model.edges {
            let arrow: String
            switch edge.kind {
            case .inherits:
                arrow = "-:>"

            case .conforms:
                arrow = "--:>"

            case .imports:
                arrow = "-->"
            }
            let safeFrom = nomnomlLabel(edge.from, stereotype: stereotypes[edge.from])
            let safeTo = nomnomlLabel(edge.to, stereotype: stereotypes[edge.to])
            lines.append("[\(safeFrom)] \(arrow) [\(safeTo)]")
        }

        return lines.joined(separator: "\n")
    }

    /// Produce a Nomnoml-safe node label, optionally augmented with a
    /// `«stereotype»` suffix. Guillemets render as a stereotype in
    /// Nomnoml output and avoid clashing with `[]` / `|` label syntax.
    static func nomnomlLabel(_ name: String, stereotype: String?) -> String {
        let escaped = name.nomnomlEscaped
        if let stereotype, !stereotype.isEmpty {
            return "\(escaped) «\(stereotype)»"
        }
        return escaped
    }
}
