/// A rendered Component diagram. Supports PlantUML, Mermaid (flowchart
/// fallback — Mermaid lacks a dedicated component dialect), and SVG. The SVG
/// path additionally produces a `componentLayout` for Studio's native canvas.
/// Nomnoml has no component dialect either, so it falls back to Mermaid and
/// reports `.mermaid` — like the sequence, activity, state, and ER emitters.
public struct ComponentScript: Sendable, DiagramOutputting {
    public let text: String
    public let format: DiagramFormat
    public let componentLayout: ComponentLayout?

    public static let empty = Self(text: "", format: .plantuml)

    public init(model: ComponentModel, configuration: Configuration = .default) {
        let drawn = configuration.format.drawn(
            plantUML: { Self.buildPlantUMLText(model: model) },
            mermaid: { Self.buildMermaidText(model: model) },
            svg: {
                let result = ComponentSVGRenderer.render(model)
                return (result.svg, result.layout)
            }
        )
        self.text = drawn.text
        self.format = drawn.format
        self.componentLayout = drawn.layout
    }

    private init(text: String, format: DiagramFormat) {
        self.text = text
        self.format = format
        self.componentLayout = nil
    }
}
