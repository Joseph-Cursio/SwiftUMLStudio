/// A rendered state machine diagram.
public struct StateScript: Sendable, DiagramOutputting {
    /// The diagram text.
    public let text: String

    /// The output format.
    public let format: DiagramFormat

    /// An empty script (used when no candidate matches).
    public static let empty = Self(text: "", format: .plantuml)

    internal init(model: StateMachineModel, configuration: Configuration) {
        // No SVG layout for state diagrams yet, so SVG is drawn as Mermaid, as Nomnoml is.
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

    // Internal rather than private so a test can call it directly.

    /// Normalize the wildcard source token `*` to PlantUML / Mermaid's initial
    /// pseudo-state `[*]`.
    static func renderStateToken(_ name: String) -> String {
        name == "*" ? "[*]" : name
    }
}
