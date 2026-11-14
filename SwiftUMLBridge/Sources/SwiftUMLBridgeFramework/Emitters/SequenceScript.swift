/// A rendered sequence diagram in PlantUML or Mermaid format.
public struct SequenceScript: Sendable, DiagramOutputting {
    /// The diagram text.
    public let text: String

    /// The output format.
    public let format: DiagramFormat

    /// Positioned sequence layout (available when format is `.svg`).
    public let sequenceLayout: SequenceLayout?

    /// Whether the entry point came to a method with a body, which the diagram starts from.
    /// `false` when it came to none, so the diagram is empty for that reason and not because the
    /// method calls nothing, which the CLI warns of (#239).
    public internal(set) var foundEntry = true

    /// An empty script (used when no entry point matches).
    public static let empty = Self(text: "", format: .plantuml)

    internal init(
        traversedEdges: [CallEdge],
        entryType: String,
        entryMethod: String,
        configuration: Configuration,
        typeLocations: [String: SourceLocation] = [:]
    ) {
        let drawn = configuration.format.drawn(
            plantUML: {
                Self.buildPlantUMLText(
                    traversedEdges: traversedEdges, entryType: entryType, entryMethod: entryMethod
                )
            },
            mermaid: {
                Self.buildMermaidText(
                    traversedEdges: traversedEdges, entryType: entryType, entryMethod: entryMethod
                )
            },
            svg: {
                let layout = SequenceSVGRenderer.computeLayout(
                    traversedEdges: traversedEdges,
                    entryType: entryType,
                    entryMethod: entryMethod,
                    typeLocations: typeLocations
                )
                return (SequenceSVGRenderer.renderFromLayout(layout), layout)
            }
        )
        self.text = drawn.text
        self.format = drawn.format
        self.sequenceLayout = drawn.layout
    }

    private init(text: String, format: DiagramFormat) {
        self.text = text
        self.format = format
        self.sequenceLayout = nil
        self.foundEntry = false
    }
}
