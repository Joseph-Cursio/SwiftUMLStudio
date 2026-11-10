import Foundation

/// A rendered activity diagram in PlantUML, Mermaid, or SVG format.
public struct ActivityScript: Sendable, DiagramOutputting {
    /// The diagram text.
    public let text: String

    /// The output format.
    public let format: DiagramFormat

    /// Positioned activity layout (available when format is `.svg`).
    public let activityLayout: ActivityLayout?

    /// Whether the entry point came to a method with a body, which the diagram draws. `false`
    /// when it came to none, so the diagram is empty for that reason and not because the method
    /// does nothing, which the CLI warns of (#239).
    public internal(set) var foundEntry = true

    /// An empty script (used when the entry point is not found).
    public static let empty = Self(text: "", format: .plantuml)

    internal init(graph: ActivityGraph, configuration: Configuration) {
        let drawn = configuration.format.drawn(
            plantUML: { Self.buildPlantUMLText(from: graph) },
            mermaid: { Self.buildMermaidText(from: graph) },
            svg: {
                let layout = ActivitySVGRenderer.computeLayout(from: graph)
                return (ActivitySVGRenderer.renderFromLayout(layout), layout)
            }
        )
        self.text = drawn.text
        self.format = drawn.format
        self.activityLayout = drawn.layout
    }

    private init(text: String, format: DiagramFormat) {
        self.text = text
        self.format = format
        self.activityLayout = nil
        self.foundEntry = false
    }

    // Internal rather than private so a test can call them directly.
    static func plantUMLEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// `|` is written as Mermaid's own entity, `#124;`: Mermaid reads `#124;` inside `&#124;`
    /// first, so `&#124;` was drawn `&|`, and `a || b` as `a &|&| b`.
    static func mermaidEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "|", with: "#124;")
    }
}
