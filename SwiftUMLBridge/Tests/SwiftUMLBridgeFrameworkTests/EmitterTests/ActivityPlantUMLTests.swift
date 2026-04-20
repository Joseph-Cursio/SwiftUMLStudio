import Testing
@testable import SwiftUMLBridgeFramework

@Suite("ActivityScript — PlantUML")
struct ActivityPlantUMLTests {

    private func makeScript(graph: ActivityGraph, format: DiagramFormat = .plantuml) -> ActivityScript {
        var config = Configuration.default
        config.format = format
        return ActivityScript(graph: graph, configuration: config)
    }

    private func smallGraph() -> ActivityGraph {
        ActivityGraph(
            nodes: [
                ActivityNode(id: 0, kind: .start, label: ""),
                ActivityNode(id: 1, kind: .end, label: ""),
                ActivityNode(id: 2, kind: .action, label: "doWork()")
            ],
            edges: [
                ActivityEdge(fromId: 0, toId: 2),
                ActivityEdge(fromId: 2, toId: 1)
            ],
            entryType: "Foo",
            entryMethod: "run"
        )
    }

    @Test("starts with @startuml")
    func startsWithStartuml() {
        let script = makeScript(graph: smallGraph())
        #expect(script.text.hasPrefix("@startuml"))
    }

    @Test("ends with @enduml")
    func endsWithEnduml() {
        let script = makeScript(graph: smallGraph())
        let lastLine = script.text.components(separatedBy: "\n").last(where: { !$0.isEmpty })
        #expect(lastLine == "@enduml")
    }

    @Test("contains title line")
    func containsTitle() {
        let script = makeScript(graph: smallGraph())
        #expect(script.text.contains("title Foo.run"))
    }

    @Test("action nodes declared with state name")
    func actionDeclaredAsState() {
        let script = makeScript(graph: smallGraph())
        #expect(script.text.contains("state \"doWork()\" as N2"))
    }

    @Test("decision nodes use <<choice>> stereotype")
    func decisionUsesChoice() {
        let graph = ActivityGraph(
            nodes: [
                ActivityNode(id: 0, kind: .start, label: ""),
                ActivityNode(id: 1, kind: .decision, label: "flag?"),
                ActivityNode(id: 2, kind: .end, label: "")
            ],
            edges: [
                ActivityEdge(fromId: 0, toId: 1),
                ActivityEdge(fromId: 1, toId: 2, label: "true")
            ],
            entryType: "Foo",
            entryMethod: "run"
        )
        let script = makeScript(graph: graph)
        #expect(script.text.contains("<<choice>>"))
    }

    @Test("fork/join use <<fork>> and <<join>> stereotypes")
    func forkJoinStereotypes() {
        let graph = ActivityGraph(
            nodes: [
                ActivityNode(id: 0, kind: .start, label: ""),
                ActivityNode(id: 1, kind: .fork, label: ""),
                ActivityNode(id: 2, kind: .join, label: ""),
                ActivityNode(id: 3, kind: .end, label: "")
            ],
            edges: [],
            entryType: "Foo",
            entryMethod: "run"
        )
        let script = makeScript(graph: graph)
        #expect(script.text.contains("<<fork>>"))
        #expect(script.text.contains("<<join>>"))
    }

    @Test("start and end references use [*]")
    func terminalUsesAsterisk() {
        let script = makeScript(graph: smallGraph())
        #expect(script.text.contains("[*] --> N2"))
        #expect(script.text.contains("N2 --> [*]"))
    }

    @Test("labeled edges include branch label after colon")
    func labeledEdgeIncludesLabel() {
        let graph = ActivityGraph(
            nodes: [
                ActivityNode(id: 0, kind: .decision, label: "cond?"),
                ActivityNode(id: 1, kind: .end, label: "")
            ],
            edges: [
                ActivityEdge(fromId: 0, toId: 1, label: "true")
            ],
            entryType: "Foo",
            entryMethod: "run"
        )
        let script = makeScript(graph: graph)
        #expect(script.text.contains(": true"))
    }

    @Test("empty graph still produces a valid @startuml/@enduml")
    func emptyGraphValid() {
        let script = makeScript(graph: ActivityGraph(entryType: "Foo", entryMethod: "run"))
        #expect(script.text.contains("@startuml"))
        #expect(script.text.contains("@enduml"))
    }

    @Test("format property reports plantuml")
    func formatIsPlantuml() {
        let script = makeScript(graph: smallGraph())
        #expect(script.format == .plantuml)
    }
}
