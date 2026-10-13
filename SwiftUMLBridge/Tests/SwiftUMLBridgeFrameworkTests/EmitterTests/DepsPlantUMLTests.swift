import Testing
@testable import SwiftUMLBridgeFramework

@Suite("DepsScript — PlantUML")
struct DepsPlantUMLTests {

    private func makeScript(edges: [DependencyEdge], format: DiagramFormat = .plantuml) -> DepsScript {
        let model = DependencyGraphModel(edges: edges)
        var config = Configuration.default
        config.format = format
        return DepsScript(model: model, configuration: config)
    }

    // MARK: - Structure

    @Test("PlantUML output starts with @startuml")
    func startsWithStartUML() {
        let script = makeScript(edges: [])
        #expect(script.text.hasPrefix("@startuml"))
    }

    @Test("PlantUML output ends with @enduml")
    func endsWithEndUML() {
        let script = makeScript(edges: [])
        #expect(script.text.hasSuffix("@enduml"))
    }

    @Test("format property is plantuml")
    func formatIsPlantuml() {
        let script = makeScript(edges: [])
        #expect(script.format == .plantuml)
    }

    // MARK: - Edge rendering

    @Test("inherits edge renders with 'inherits' label")
    func inheritsEdgeRendered() {
        let edge = DependencyEdge(from: "Dog", to: "Animal", kind: .inherits)
        let script = makeScript(edges: [edge])
        #expect(script.text.contains("Dog --> Animal : inherits"))
    }

    @Test("conforms edge renders with 'conforms' label")
    func conformsEdgeRendered() {
        let edge = DependencyEdge(from: "Report", to: "Printable", kind: .conforms)
        let script = makeScript(edges: [edge])
        #expect(script.text.contains("Report --> Printable : conforms"))
    }

    @Test("imports edge renders with 'imports' label")
    func importsEdgeRendered() {
        let edge = DependencyEdge(from: "App", to: "Foundation", kind: .imports)
        let script = makeScript(edges: [edge])
        #expect(script.text.contains("App --> Foundation : imports"))
    }

    @Test("multiple edges all appear in output")
    func multipleEdgesAllAppear() {
        let edges = [
            DependencyEdge(from: "A", to: "B", kind: .conforms),
            DependencyEdge(from: "B", to: "C", kind: .inherits),
            DependencyEdge(from: "C", to: "D", kind: .imports)
        ]
        let script = makeScript(edges: edges)
        #expect(script.text.contains("A --> B"))
        #expect(script.text.contains("B --> C"))
        #expect(script.text.contains("C --> D"))
    }

    // MARK: - Cycle annotation

    @Test("cyclic nodes are annotated with a note block")
    func cyclicNodesAnnotated() {
        let edges = [
            DependencyEdge(from: "Alpha", to: "Beta", kind: .imports),
            DependencyEdge(from: "Beta", to: "Alpha", kind: .imports)
        ]
        let script = makeScript(edges: edges)
        #expect(script.text.contains("CyclicDependencies"))
        #expect(script.text.contains("Alpha"))
        #expect(script.text.contains("Beta"))
    }

    @Test("no cycles means no cycle note block")
    func noCyclesNoNote() {
        let edges = [
            DependencyEdge(from: "A", to: "B", kind: .conforms)
        ]
        let script = makeScript(edges: edges)
        #expect(script.text.contains("CyclicDependencies") == false)
    }

    // MARK: - encodeText

    @Test("encodeText decodes back to exactly the script, however few edges", arguments: [0, 1, 20])
    func encodeTextRoundTrips(edgeCount: Int) {
        // With no edges the script is just "@startuml\n@enduml", and with one it is barely
        // longer. Neither compresses below its own length, so both once encoded to "" (#57).
        let edges = (0..<edgeCount).map { num in
            DependencyEdge(from: "Dog\(num)", to: "Animal\(num)", kind: .inherits)
        }
        let script = makeScript(edges: edges)
        #expect(PlantUMLTextDecoding.decode(script.encodeText()) == script.text)
    }
}
