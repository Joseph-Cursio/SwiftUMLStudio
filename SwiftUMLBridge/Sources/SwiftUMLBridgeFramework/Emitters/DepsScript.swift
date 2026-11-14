import Foundation

/// A rendered dependency graph in PlantUML or Mermaid format.
public struct DepsScript: Sendable, DiagramOutputting {
    /// The diagram text.
    public let text: String

    /// The output format.
    public let format: DiagramFormat

    /// Positioned layout graph (available when format is `.svg`).
    public let layoutGraph: LayoutGraph?

    internal init(model: DependencyGraphModel, configuration: Configuration) {
        self.format = configuration.format
        let cycleNodes = model.detectCycles()

        switch configuration.format {
        case .plantuml:
            self.text = Self.buildPlantUMLText(model: model, cycleNodes: cycleNodes)
            self.layoutGraph = nil

        case .mermaid:
            self.text = Self.buildMermaidText(model: model, cycleNodes: cycleNodes)
            self.layoutGraph = nil

        case .nomnoml:
            self.text = Self.buildNomnomlText(model: model, cycleNodes: cycleNodes)
            self.layoutGraph = nil

        case .svg:
            let result = Self.buildSVGWithGraph(model: model)
            self.text = result.text
            self.layoutGraph = result.graph
        }
    }

    // Internal rather than private so a test can call it directly.

    /// Convert a type/module name to a Mermaid-safe identifier (no spaces, generics, etc.).
    static func mermaidId(_ name: String) -> String {
        name
            .replacingOccurrences(of: "<", with: "_")
            .replacingOccurrences(of: ">", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: "-", with: "_")
    }
}
