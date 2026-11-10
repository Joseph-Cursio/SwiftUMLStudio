import Foundation

// MARK: - PlantUML

extension ERScript {
    static func buildPlantUMLText(model: ERModel) -> String {
        var lines: [String] = ["@startuml"]

        for entity in model.entities {
            lines.append(contentsOf: plantUMLEntityLines(entity))
            lines.append("")
        }

        for relationship in model.relationships {
            let leftSymbol = Self.mermaidLeftSymbol(for: relationship.fromCardinality)
            let rightSymbol = Self.mermaidRightSymbol(for: relationship.toCardinality)
            let label = Self.sanitizeLabel(relationship.label)
            lines.append(
                "\(relationship.from) \(leftSymbol)--\(rightSymbol) \(relationship.toEntity) : \(label)"
            )
        }

        lines.append("@enduml")
        return lines.joined(separator: "\n")
    }

    static func plantUMLEntityLines(_ entity: EREntity) -> [String] {
        var lines: [String] = ["entity \"\(entity.name)\" {"]
        let primaries = entity.attributes.filter(\.isPrimaryKey)
        let others = entity.attributes.filter { !$0.isPrimaryKey }

        for attribute in primaries {
            lines.append("  * \(plantUMLAttributeText(attribute))")
        }
        if !primaries.isEmpty, !others.isEmpty {
            lines.append("  --")
        }
        for attribute in others {
            lines.append("  \(plantUMLAttributeText(attribute))")
        }
        lines.append("}")
        return lines
    }

    static func plantUMLAttributeText(_ attribute: ERAttribute) -> String {
        var text = "\(attribute.name) : \(attribute.type)"
        if attribute.isOptional {
            text += "?"
        }
        var stereotypes: [String] = []
        if attribute.isUnique, !attribute.isPrimaryKey {
            stereotypes.append("UK")
        }
        if attribute.isTransient {
            stereotypes.append("transient")
        }
        if !stereotypes.isEmpty {
            text += " <<\(stereotypes.joined(separator: ", "))>>"
        }
        return text
    }
}
