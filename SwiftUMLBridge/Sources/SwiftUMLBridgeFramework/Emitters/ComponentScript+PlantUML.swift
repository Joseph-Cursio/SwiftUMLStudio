// MARK: - PlantUML

extension ComponentScript {
    static func buildPlantUMLText(model: ComponentModel) -> String {
        var lines: [String] = ["@startuml"]
        var ids = DiagramIdentifiers(sanitize: safeAlias)
        for component in model.components {
            let stereotype = stereotypeText(for: component.kind)
            lines.append("component \"\(component.name)\" as \(ids.id(for: component.name)) \(stereotype) {")
            for interfaceName in component.providedInterfaces {
                lines.append("  [\(interfaceName)]")
            }
            lines.append("}")
        }
        for dependency in model.dependencies {
            lines.append("\(ids.id(for: dependency.from)) ..> \(ids.id(for: dependency.to))")
        }
        lines.append("@enduml")
        return lines.joined(separator: "\n")
    }

    static func stereotypeText(for kind: Component.Kind) -> String {
        switch kind {
        case .executable: return "<<executable>>"
        case .library:    return "<<library>>"
        case .test:       return "<<test>>"
        case .other:      return ""
        }
    }
}
