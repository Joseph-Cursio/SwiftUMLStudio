import Testing
@testable import SwiftUMLBridgeFramework

@Suite("DepsScript — SVG")
struct DepsSVGTests {

    private func makeScript(edges: [DependencyEdge]) -> DepsScript {
        let model = DependencyGraphModel(edges: edges)
        var config = Configuration.default
        config.format = .svg
        return DepsScript(model: model, configuration: config)
    }

    // MARK: - Structure

    @Test("SVG output starts with '<svg'")
    func startsWithSVGTag() {
        let edge = DependencyEdge(from: "Alpha", to: "Beta", kind: .conforms)
        let script = makeScript(edges: [edge])
        #expect(script.text.hasPrefix("<svg"))
    }

    @Test("format property is svg")
    func formatIsSVG() {
        let script = makeScript(edges: [DependencyEdge(from: "Src", to: "Dst", kind: .imports)])
        #expect(script.format == .svg)
    }

    // MARK: - Layout graph

    @Test("layoutGraph is populated for SVG format")
    func layoutGraphIsPopulated() {
        let edge = DependencyEdge(from: "Alpha", to: "Beta", kind: .conforms)
        let script = makeScript(edges: [edge])
        #expect(script.layoutGraph != nil)
    }

    @Test("layoutGraph has nodes matching edge endpoints")
    func layoutGraphHasExpectedNodes() {
        let edge = DependencyEdge(from: "Service", to: "Repository", kind: .imports)
        let script = makeScript(edges: [edge])
        let nodeLabels = script.layoutGraph?.nodes.map(\.label) ?? []
        #expect(nodeLabels.contains("Service"))
        #expect(nodeLabels.contains("Repository"))
    }

    @Test("layoutGraph has edges matching the model")
    func layoutGraphHasExpectedEdges() {
        let edges = [
            DependencyEdge(from: "Alpha", to: "Beta", kind: .conforms),
            DependencyEdge(from: "Beta", to: "Gamma", kind: .inherits)
        ]
        let script = makeScript(edges: edges)
        #expect(script.layoutGraph?.edges.count == 2)
    }

    // MARK: - SVG content

    @Test("SVG output contains node names as text elements")
    func svgContainsNodeNames() {
        let edge = DependencyEdge(from: "Controller", to: "View", kind: .imports)
        let script = makeScript(edges: [edge])
        #expect(script.text.contains("Controller"))
        #expect(script.text.contains("View"))
    }

    @Test("SVG output contains closing svg tag")
    func svgContainsClosingTag() {
        let edge = DependencyEdge(from: "Alpha", to: "Beta", kind: .conforms)
        let script = makeScript(edges: [edge])
        #expect(script.text.contains("</svg>"))
    }

    @Test("multiple edges produce SVG with all node names")
    func multipleEdgesAllNodesInSVG() {
        let edges = [
            DependencyEdge(from: "AppModel", to: "DataStore", kind: .imports),
            DependencyEdge(from: "DataStore", to: "Network", kind: .imports),
            DependencyEdge(from: "Network", to: "Foundation", kind: .imports)
        ]
        let script = makeScript(edges: edges)
        #expect(script.text.contains("AppModel"))
        #expect(script.text.contains("DataStore"))
        #expect(script.text.contains("Network"))
        #expect(script.text.contains("Foundation"))
    }

    // MARK: - Empty graph

    @Test("empty edges still produce valid SVG")
    func emptyEdgesProduceValidSVG() {
        let script = makeScript(edges: [])
        #expect(script.text.hasPrefix("<svg"))
        #expect(script.text.contains("</svg>"))
    }

    @Test("empty edges produce empty layout graph")
    func emptyEdgesProduceEmptyLayoutGraph() {
        let script = makeScript(edges: [])
        #expect(script.layoutGraph != nil)
        #expect(script.layoutGraph?.nodes.isEmpty == true)
    }
}
