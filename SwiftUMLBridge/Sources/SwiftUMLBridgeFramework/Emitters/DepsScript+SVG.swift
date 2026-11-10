// MARK: - SVG

extension DepsScript {
    static func buildSVGWithGraph(model: DependencyGraphModel) -> (text: String, graph: LayoutGraph) {
        let graph = LayoutGraphBuilder.buildDependencyGraph(from: model)
        let positioned = DagreLayoutEngine.layout(graph)
        return (SVGRenderer.render(positioned), positioned)
    }
}
