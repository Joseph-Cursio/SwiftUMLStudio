import Testing
@testable import SwiftUMLBridgeFramework

@Suite("ActivityScript — Mermaid")
struct ActivityMermaidTests {

    private func makeScript(graph: ActivityGraph) -> ActivityScript {
        var config = Configuration.default
        config.format = .mermaid
        return ActivityScript(graph: graph, configuration: config)
    }

    @Test("starts with flowchart TD")
    func startsWithFlowchartHeader() {
        let graph = ActivityGraph(
            nodes: [ActivityNode(id: 0, kind: .start, label: "")],
            edges: [],
            entryType: "Foo", entryMethod: "run"
        )
        let script = makeScript(graph: graph)
        #expect(script.text.hasPrefix("flowchart TD"))
    }

    @Test("title rendered as a Mermaid comment")
    func titleInComment() {
        let graph = ActivityGraph(
            nodes: [ActivityNode(id: 0, kind: .start, label: "")],
            edges: [],
            entryType: "Foo", entryMethod: "run"
        )
        let script = makeScript(graph: graph)
        #expect(script.text.contains("%% title: Foo.run"))
    }

    @Test("action rendered as rectangle with label")
    func actionIsRectangle() {
        let graph = ActivityGraph(
            nodes: [
                ActivityNode(id: 0, kind: .action, label: "doWork()")
            ],
            edges: [],
            entryType: "Foo", entryMethod: "run"
        )
        let script = makeScript(graph: graph)
        #expect(script.text.contains("N0[\"doWork()\"]"))
    }

    @Test("decision rendered as diamond")
    func decisionIsDiamond() {
        let graph = ActivityGraph(
            nodes: [
                ActivityNode(id: 0, kind: .decision, label: "cond?")
            ],
            edges: [],
            entryType: "Foo", entryMethod: "run"
        )
        let script = makeScript(graph: graph)
        #expect(script.text.contains("N0{\"cond?\"}"))
    }

    @Test("edge label rendered inside |…|")
    func edgeLabelRendered() {
        let graph = ActivityGraph(
            nodes: [
                ActivityNode(id: 0, kind: .decision, label: "cond?"),
                ActivityNode(id: 1, kind: .action, label: "yes")
            ],
            edges: [
                ActivityEdge(fromId: 0, toId: 1, label: "true")
            ],
            entryType: "Foo", entryMethod: "run"
        )
        let script = makeScript(graph: graph)
        #expect(script.text.contains("N0 -->|true| N1"))
    }

    @Test("unlabeled edges use plain arrow")
    func unlabeledEdgePlain() {
        let graph = ActivityGraph(
            nodes: [
                ActivityNode(id: 0, kind: .action, label: "a"),
                ActivityNode(id: 1, kind: .action, label: "b")
            ],
            edges: [
                ActivityEdge(fromId: 0, toId: 1)
            ],
            entryType: "Foo", entryMethod: "run"
        )
        let script = makeScript(graph: graph)
        #expect(script.text.contains("N0 --> N1"))
    }

    @Test("async action includes await prefix in label")
    func asyncActionHasAwaitPrefix() {
        let graph = ActivityGraph(
            nodes: [
                ActivityNode(id: 0, kind: .action, label: "fetch()", isAsync: true)
            ],
            edges: [],
            entryType: "Foo", entryMethod: "run"
        )
        let script = makeScript(graph: graph)
        #expect(script.text.contains("await fetch()"))
    }

    @Test("format property reports mermaid")
    func formatIsMermaid() {
        let graph = ActivityGraph(
            nodes: [ActivityNode(id: 0, kind: .start, label: "")],
            edges: [],
            entryType: "Foo", entryMethod: "run"
        )
        let script = makeScript(graph: graph)
        #expect(script.format == .mermaid)
    }
}
