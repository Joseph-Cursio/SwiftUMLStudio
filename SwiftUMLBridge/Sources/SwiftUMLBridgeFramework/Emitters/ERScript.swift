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

// MARK: - Emitter stubs

private extension ERScript {
    /// Placeholder — real PlantUML `entity` syntax lands in a follow-up commit.
    static func buildPlantUMLText(model: ERModel) -> String { "" }

    /// Placeholder — real Mermaid `erDiagram` syntax lands in a follow-up commit.
    static func buildMermaidText(model: ERModel) -> String { "" }
}

extension ERScript: DiagramOutputting {}
