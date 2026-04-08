import Testing
@testable import SwiftUMLBridgeFramework

@Suite("DepsScript — Nomnoml")
struct DepsNomnomlTests {

    private func makeScript(edges: [DependencyEdge]) -> DepsScript {
        let model = DependencyGraphModel(edges: edges)
        var config = Configuration.default
        config.format = .nomnoml
        return DepsScript(model: model, configuration: config)
    }

    // MARK: - Structure

    @Test("nomnoml output starts with '#direction: down'")
    func startsWithDirection() {
        let script = makeScript(edges: [])
        #expect(script.text.hasPrefix("#direction: down"))
    }

    @Test("format property is nomnoml")
    func formatIsNomnoml() {
        let script = makeScript(edges: [])
        #expect(script.format == .nomnoml)
    }

    @Test("layoutGraph is nil for nomnoml format")
    func layoutGraphIsNil() {
        let script = makeScript(edges: [])
        #expect(script.layoutGraph == nil)
    }

    @Test("header contains fontSize directive")
    func headerContainsFontSize() {
        let script = makeScript(edges: [])
        #expect(script.text.contains("#fontSize: 12"))
    }

    @Test("header contains spacing directive")
    func headerContainsSpacing() {
        let script = makeScript(edges: [])
        #expect(script.text.contains("#spacing: 60"))
    }

    @Test("header contains edges directive")
    func headerContainsEdges() {
        let script = makeScript(edges: [])
        #expect(script.text.contains("#edges: rounded"))
    }

    // MARK: - Edge arrows by kind

    @Test("inherits edge uses '-:>' arrow")
    func inheritsEdgeArrow() {
        let edge = DependencyEdge(from: "Dog", to: "Animal", kind: .inherits)
        let script = makeScript(edges: [edge])
        #expect(script.text.contains("-:>"))
        #expect(script.text.contains("[Dog] -:> [Animal]"))
    }

    @Test("conforms edge uses '--:>' arrow")
    func conformsEdgeArrow() {
        let edge = DependencyEdge(from: "Report", to: "Printable", kind: .conforms)
        let script = makeScript(edges: [edge])
        #expect(script.text.contains("--:>"))
        #expect(script.text.contains("[Report] --:> [Printable]"))
    }

    @Test("imports edge uses '-->' arrow")
    func importsEdgeArrow() {
        let edge = DependencyEdge(from: "App", to: "Foundation", kind: .imports)
        let script = makeScript(edges: [edge])
        #expect(script.text.contains("-->"))
        #expect(script.text.contains("[App] --> [Foundation]"))
    }

    @Test("multiple edges all appear in output")
    func multipleEdgesAllAppear() {
        let edges = [
            DependencyEdge(from: "Alpha", to: "Beta", kind: .conforms),
            DependencyEdge(from: "Beta", to: "Gamma", kind: .inherits),
            DependencyEdge(from: "Gamma", to: "Delta", kind: .imports)
        ]
        let script = makeScript(edges: edges)
        #expect(script.text.contains("[Alpha] --:> [Beta]"))
        #expect(script.text.contains("[Beta] -:> [Gamma]"))
        #expect(script.text.contains("[Gamma] --> [Delta]"))
    }

    // MARK: - Cycle annotation

    @Test("cyclic nodes receive warning style annotation")
    func cyclicNodesReceiveWarning() {
        let edges = [
            DependencyEdge(from: "Alpha", to: "Beta", kind: .imports),
            DependencyEdge(from: "Beta", to: "Alpha", kind: .imports)
        ]
        let script = makeScript(edges: edges)
        #expect(script.text.contains("#.warning: fill=#ffcccc stroke=#cc0000"))
        #expect(script.text.contains("<warning>"))
    }

    @Test("cyclic nodes comment lists the node names")
    func cyclicNodesCommentListsNames() {
        let edges = [
            DependencyEdge(from: "Alpha", to: "Beta", kind: .imports),
            DependencyEdge(from: "Beta", to: "Alpha", kind: .imports)
        ]
        let script = makeScript(edges: edges)
        #expect(script.text.contains("// Cyclic nodes: Alpha, Beta"))
    }

    @Test("no cycles means no warning annotation")
    func noCyclesNoWarning() {
        let edges = [
            DependencyEdge(from: "Alpha", to: "Beta", kind: .conforms)
        ]
        let script = makeScript(edges: edges)
        #expect(script.text.contains("#.warning") == false)
        #expect(script.text.contains("<warning>") == false)
    }

    // MARK: - Nomnoml escaping in dependency names

    @Test("brackets in node names are escaped to parentheses")
    func bracketsEscapedInNodeNames() {
        let edge = DependencyEdge(from: "Array[Int]", to: "Base", kind: .imports)
        let script = makeScript(edges: [edge])
        // The node name inside [] would conflict with nomnoml syntax
        #expect(script.text.contains("Array(Int)"))
    }

    @Test("pipe characters in node names are escaped to slashes")
    func pipesEscapedInNodeNames() {
        let edge = DependencyEdge(from: "A|B", to: "Target", kind: .imports)
        let script = makeScript(edges: [edge])
        #expect(script.text.contains("A/B"))
    }

    @Test("semicolons in node names are escaped to commas")
    func semicolonsEscapedInNodeNames() {
        let edge = DependencyEdge(from: "X;Y", to: "Target", kind: .imports)
        let script = makeScript(edges: [edge])
        #expect(script.text.contains("X,Y"))
    }

    // MARK: - Empty edges

    @Test("no edges produces only header lines")
    func noEdgesProducesOnlyHeader() {
        let script = makeScript(edges: [])
        let lines = script.text.components(separatedBy: "\n")
        // All lines should be directives (start with #)
        for line in lines {
            #expect(line.hasPrefix("#"))
        }
    }
}
