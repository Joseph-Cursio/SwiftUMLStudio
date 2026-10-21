import Foundation

/// A diagram's text in the format a script drew it in, with its SVG layout when that is SVG.
struct DrawnDiagram<Layout> {
    let text: String
    /// The format `text` is in, which the script reports. Presenters and Studio pick a renderer
    /// by it, so a fallback reports `.mermaid`, not the format that was asked for.
    let format: DiagramFormat
    let layout: Layout?
}

extension DiagramFormat {
    /// Draws a diagram in this format with the builders a script has, or as Mermaid in a format
    /// it has no builder for (#209). The sequence, activity, component, state and ER scripts each
    /// have a PlantUML and a Mermaid builder and no Nomnoml one, so `.nomnoml` is always drawn as
    /// Mermaid, as is `.svg` when `svg` is `nil`. Mermaid stands in because every one of these
    /// diagram kinds has a Mermaid dialect, which Studio and `BrowserPresenter` render.
    func drawn<Layout>(
        plantUML: () -> String,
        mermaid: () -> String,
        svg: (() -> (text: String, layout: Layout))?
    ) -> DrawnDiagram<Layout> {
        if self == .plantuml {
            return DrawnDiagram(text: plantUML(), format: .plantuml, layout: nil)
        }
        if self == .svg, let svg {
            let drawn = svg()
            return DrawnDiagram(text: drawn.text, format: .svg, layout: drawn.layout)
        }
        return DrawnDiagram(text: mermaid(), format: .mermaid, layout: nil)
    }

    /// Draws a diagram that has no SVG builder, so `.svg` is drawn as Mermaid too.
    func drawn(plantUML: () -> String, mermaid: () -> String) -> DrawnDiagram<Never> {
        drawn(plantUML: plantUML, mermaid: mermaid, svg: nil)
    }
}
