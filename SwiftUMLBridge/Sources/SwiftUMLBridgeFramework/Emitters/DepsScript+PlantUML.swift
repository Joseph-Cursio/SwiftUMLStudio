// MARK: - PlantUML

extension DepsScript {
    static func buildPlantUMLText(model: DependencyGraphModel, cycleNodes: Set<String>) -> String {
        var lines: [String] = ["@startuml"]

        let nodeDeclarations = packageNodeDeclarations(model: model)
        if !nodeDeclarations.isEmpty {
            lines.append(contentsOf: nodeDeclarations)
            lines.append("")
        }

        // Emit one edge per line
        for edge in model.edges {
            lines.append("\(edge.from) --> \(edge.toNode) : \(edge.kind.rawValue)")
        }

        // Annotate cycle nodes with a note block
        if !cycleNodes.isEmpty {
            let sorted = cycleNodes.sorted()
            lines.append("")
            lines.append("note as CyclicDependencies")
            lines.append("  Cyclic nodes: \(sorted.joined(separator: ", "))")
            lines.append("end note")
        }

        lines.append("@enduml")
        return lines.joined(separator: "\n")
    }

    /// When the model carries SPM provenance — either `targetKinds`
    /// (modules-mode + --package) or per-edge module tags (types-mode +
    /// --package) — emit explicit PlantUML node declarations so each node
    /// is stereotyped with its module / target kind.
    static func packageNodeDeclarations(model: DependencyGraphModel) -> [String] {
        let stereotypes = Self.nodeStereotypes(model: model)
        guard !stereotypes.isEmpty else { return [] }
        // Modules-mode + --package: emit one `component` line per target.
        if !model.targetKinds.isEmpty {
            return stereotypes.sorted { $0.key < $1.key }.map { name, stereotype in
                "component \"\(name)\" as \(name) <<\(stereotype)>>"
            }
        }
        // Types-mode + --package: emit one `class` line per known type.
        return stereotypes.sorted { $0.key < $1.key }.map { name, stereotype in
            "class \"\(name)\" as \(name) <<\(stereotype)>>"
        }
    }
}
