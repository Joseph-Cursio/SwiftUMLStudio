import Foundation

/// A rendered Entity-Relationship diagram.
public struct ERScript: Sendable, DiagramOutputting {
    public let text: String
    public let format: DiagramFormat

    /// An empty script (returned when no `@Model` types are found).
    public static let empty = Self(text: "", format: .plantuml)

    internal init(model: ERModel, configuration: Configuration) {
        // No SVG layout for ER diagrams yet, so SVG is drawn as Mermaid, as Nomnoml is.
        let drawn = configuration.format.drawn(
            plantUML: { Self.buildPlantUMLText(model: model) },
            mermaid: { Self.buildMermaidText(model: model) }
        )
        self.text = drawn.text
        self.format = drawn.format
    }

    private init(text: String, format: DiagramFormat) {
        self.text = text
        self.format = format
    }

    // Internal rather than private so a test can call them directly.

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
