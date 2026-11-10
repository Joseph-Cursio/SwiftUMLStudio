// MARK: - Mermaid (flowchart fallback — Mermaid has no component dialect)

extension ComponentScript {
    static func buildMermaidText(model: ComponentModel) -> String {
        var lines: [String] = ["flowchart TD"]
        var ids = DiagramIdentifiers(sanitize: safeAlias)
        for component in model.components {
            let alias = ids.id(for: component.name)
            // Use Mermaid's subgraph for the component box; one line per
            // provided interface inside.
            lines.append("    subgraph \(alias)[\"\(component.name)\"]")
            for interfaceName in component.providedInterfaces {
                // Keyed apart from component names: interface `B` of `A` and a component named
                // `A_B` both sanitize to `A_B`, and must stay two nodes.
                let interfaceId = ids.id(
                    forKey: "\(component.name)\u{0}\(interfaceName)",
                    sanitizing: "\(component.name)_\(interfaceName)"
                )
                lines.append("        \(interfaceId)[\"\(interfaceName)\"]")
            }
            lines.append("    end")
        }
        for dependency in model.dependencies {
            lines.append("    \(ids.id(for: dependency.from)) -.-> \(ids.id(for: dependency.toComponent))")
        }
        return lines.joined(separator: "\n")
    }
}
