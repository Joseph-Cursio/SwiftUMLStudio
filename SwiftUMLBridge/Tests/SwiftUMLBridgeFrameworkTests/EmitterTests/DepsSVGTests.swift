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

    @Test("a module directory named with a backslash is laid out by dagre",
          arguments: ["Old\\Code", "Trail\\"])
    func backslashModuleIsLaidOut(name: String) throws {
        let edge = DependencyEdge(from: name, to: "Foundation", kind: .imports)
        let graph = try #require(makeScript(edges: [edge]).layoutGraph)
        let module = try #require(graph.nodes.first { $0.id == name })
        let foundation = try #require(graph.nodes.first { $0.id == "Foundation" })
        // Not left at the origin, and not on the grid fallback's single row.
        #expect(module.posX != 0 || module.posY != 0)
        #expect(module.posY != foundation.posY)
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

    @Test("a module name containing a double hyphen leaves the SVG well-formed")
    func doubleHyphenModuleNameIsWellFormed() {
        let script = makeScript(edges: [DependencyEdge(from: "Old--Code", to: "Foundation", kind: .imports)])
        #expect(WellFormedXML.error(in: script.text) == nil)
        #expect(script.text.contains(">Old--Code</text>"))
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
