import Foundation

/// A rendered Entity-Relationship diagram.
public struct ERScript: Sendable {
    public let text: String
    public let format: DiagramFormat

    /// An empty script (returned when no `@Model` types are found).
    public static let empty = ERScript(text: "", format: .plantuml)

    public func encodeText() -> String {
        DiagramText(rawValue: text).encodedValue
    }

    internal init(model: ERModel, configuration: Configuration) {
        switch configuration.format {
        case .plantuml:
            self.text = ERScript.buildPlantUMLText(model: model)
            self.format = .plantuml
        case .mermaid:
            self.text = ERScript.buildMermaidText(model: model)
            self.format = .mermaid
        case .nomnoml:
            // Nomnoml has no ER-specific syntax; fall back to Mermaid text so
            // DiagramWebView can still render something (matches StateScript).
            self.text = ERScript.buildMermaidText(model: model)
            self.format = .nomnoml
        case .svg:
            // No native SVG layout for ER yet; piggyback on the Mermaid pipeline
            // so DiagramWebView routes through MermaidHTMLBuilder.
            self.text = ERScript.buildMermaidText(model: model)
            self.format = .mermaid
        }
    }

    private init(text: String, format: DiagramFormat) {
        self.text = text
        self.format = format
    }
}

// MARK: - PlantUML

private extension ERScript {
    /// Placeholder — real PlantUML `entity` syntax lands in a follow-up commit.
    static func buildPlantUMLText(model: ERModel) -> String { "" }
}

// MARK: - Mermaid

private extension ERScript {
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

    /// Mermaid type tokens may not contain whitespace, brackets, or angle
    /// brackets. Collapse any such characters to underscores so the parser
    /// accepts the output.
    static func sanitizeType(_ raw: String) -> String {
        var sanitized = ""
        for scalar in raw.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "_" {
                sanitized.unicodeScalars.append(scalar)
            } else {
                sanitized += "_"
            }
        }
        return sanitized.isEmpty ? "Unknown" : sanitized
    }

    static func sanitizeLabel(_ raw: String) -> String {
        raw.isEmpty ? "relates" : raw
    }
}

extension ERScript: DiagramOutputting {}
