import Foundation

// MARK: - Mermaid

extension ERScript {
    static func buildMermaidText(model: ERModel) -> String {
        var lines: [String] = ["erDiagram"]

        for relationship in model.relationships {
            let leftSymbol = mermaidLeftSymbol(for: relationship.fromCardinality)
            let rightSymbol = mermaidRightSymbol(for: relationship.toCardinality)
            let label = sanitizeLabel(relationship.label)
            lines.append(
                "    \(relationship.from) \(leftSymbol)--\(rightSymbol) \(relationship.toEntity) : \(label)"
            )
        }

        for entity in model.entities {
            lines.append("    \(entity.name) {")
            for attribute in entity.attributes {
                lines.append("        \(mermaidAttributeLine(attribute))")
            }
            lines.append("    }")
        }

        return lines.joined(separator: "\n")
    }

    /// Left-side crow's-foot symbol — describes how many of the *left* entity
    /// relate to one of the right entity.
    static func mermaidLeftSymbol(for cardinality: ERCardinality) -> String {
        switch cardinality {
        case .exactlyOne: return "||"
        case .zeroOrOne: return "|o"
        case .zeroOrMany: return "}o"
        case .oneOrMany: return "}|"
        }
    }

    /// Right-side crow's-foot symbol — describes how many of the *right* entity
    /// relate to one of the left entity.
    static func mermaidRightSymbol(for cardinality: ERCardinality) -> String {
        switch cardinality {
        case .exactlyOne: return "||"
        case .zeroOrOne: return "o|"
        case .zeroOrMany: return "o{"
        case .oneOrMany: return "|{"
        }
    }

    static func mermaidAttributeLine(_ attribute: ERAttribute) -> String {
        let type = sanitizeType(attribute.type)
        var line = "\(type) \(attribute.name)"
        if attribute.isPrimaryKey {
            line += " PK"
        } else if attribute.isUnique {
            line += " UK"
        }
        if attribute.isTransient {
            line += " \"transient\""
        }
        return line
    }
}
