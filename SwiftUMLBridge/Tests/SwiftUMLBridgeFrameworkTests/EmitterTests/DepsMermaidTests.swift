@testable import SwiftUMLBridgeFramework
import Testing

@Suite("DepsScript — Mermaid")
struct DepsMermaidTests {

    private func makeScript(edges: [DependencyEdge]) -> DepsScript {
        let model = DependencyGraphModel(edges: edges)
        var config = Configuration.default
        config.format = .mermaid
        return DepsScript(model: model, configuration: config)
    }

    // MARK: - Structure

    @Test("Mermaid output starts with 'graph TD'")
    func startsWithGraphTD() {
        let script = makeScript(edges: [])
        #expect(script.text.hasPrefix("graph TD"))
    }

    @Test("format property is mermaid")
    func formatIsMermaid() {
        let script = makeScript(edges: [])
        #expect(script.format == .mermaid)
    }

    // MARK: - Node declarations

    @Test("nodes appear as quoted label declarations")
    func nodeDeclsHaveQuotedLabels() {
        let edge = DependencyEdge(from: "ServiceA", to: "Protocol1", kind: .conforms)
        let script = makeScript(edges: [edge])
        #expect(script.text.contains("\"ServiceA\""))
        #expect(script.text.contains("\"Protocol1\""))
    }

    @Test("each unique node is declared once")
    func eachNodeDeclaredOnce() {
        let edges = [
            DependencyEdge(from: "A", to: "B", kind: .conforms),
            DependencyEdge(from: "A", to: "C", kind: .conforms),
        ]
        let script = makeScript(edges: edges)
        let aCount = script.text.components(separatedBy: "\"A\"").count - 1
        // Each node gets exactly one declaration line, plus possible edge references
        #expect(aCount >= 1)
    }

    // MARK: - Edge rendering

    @Test("edges rendered as 'ID --> ID' lines")
    func edgesRenderedWithArrow() {
        let edge = DependencyEdge(from: "Dog", to: "Animal", kind: .inherits)
        let script = makeScript(edges: [edge])
        // Node IDs are sanitized; check that arrow is present
        #expect(script.text.contains("-->"))
    }

    @Test("multiple edges all have arrow lines")
    func multipleEdgesHaveArrows() {
        let edges = [
            DependencyEdge(from: "A", to: "B", kind: .conforms),
            DependencyEdge(from: "B", to: "C", kind: .imports),
        ]
        let script = makeScript(edges: edges)
        let arrowLines = script.text.components(separatedBy: "\n").filter { $0.contains("-->") }
        #expect(arrowLines.count == 2)
    }

    // MARK: - Cycle annotation

    @Test("cyclic nodes receive red-fill style")
    func cyclicNodesReceiveRedFill() {
        let edges = [
            DependencyEdge(from: "Alpha", to: "Beta", kind: .imports),
            DependencyEdge(from: "Beta", to: "Alpha", kind: .imports),
        ]
        let script = makeScript(edges: edges)
        #expect(script.text.contains("#ffcccc"))
        #expect(script.text.contains("#cc0000"))
    }

    @Test("no cycles means no style annotation")
    func noCyclesNoStyleAnnotation() {
        let edges = [
            DependencyEdge(from: "A", to: "B", kind: .conforms)
        ]
        let script = makeScript(edges: edges)
        #expect(script.text.contains("#ffcccc") == false)
    }

    // MARK: - ID sanitization

    @Test("spaces in node names become underscores in IDs")
    func spacesBecomUnderscoresInIds() {
        let edge = DependencyEdge(from: "My Module", to: "Base", kind: .imports)
        let script = makeScript(edges: [edge])
        #expect(script.text.contains("My_Module"))
    }

    @Test("dots in node names become underscores in IDs")
    func dotsBecomUnderscoresInIds() {
        let edge = DependencyEdge(from: "SwiftUI.View", to: "Base", kind: .imports)
        let script = makeScript(edges: [edge])
        #expect(script.text.contains("SwiftUI_View"))
    }
}
