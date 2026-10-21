import Testing
@testable import SwiftUMLBridgeFramework

@Suite("ActivityScript — Mermaid")
struct ActivityMermaidTests {

    private func makeScript(graph: ActivityGraph, format: DiagramFormat = .mermaid) -> ActivityScript {
        var config = Configuration.default
        config.format = format
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
        #expect(script.text.contains("N0 -->|\"true\"| N1"))
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

    @Test("nomnoml format falls back to Mermaid text, reports mermaid")
    func nomnomlFallsBackToMermaid() {
        let graph = ActivityGraph(
            nodes: [ActivityNode(id: 0, kind: .start, label: "")],
            edges: [],
            entryType: "Foo", entryMethod: "run"
        )
        let script = makeScript(graph: graph, format: .nomnoml)
        #expect(script.format == .mermaid)
        #expect(script.text.hasPrefix("flowchart TD"))
    }
}

/// Mermaid 11 rejects a `(` or `[` in a bare edge label, and with it the whole diagram, and reads
/// `#124;` inside `&#124;` so that `|` was drawn `&|`.
@Suite("Activity Mermaid label escaping")
struct ActivityMermaidLabelEscapingTests {

    private func mermaid(edgeLabel: String, nodeLabel: String = "cond?") -> String {
        let graph = ActivityGraph(
            nodes: [
                ActivityNode(id: 0, kind: .decision, label: nodeLabel),
                ActivityNode(id: 1, kind: .action, label: "next")
            ],
            edges: [ActivityEdge(fromId: 0, toId: 1, label: edgeLabel)],
            entryType: "Foo", entryMethod: "run"
        )
        var config = Configuration.default
        config.format = .mermaid
        return ActivityScript(graph: graph, configuration: config).text
    }

    @Test("an edge label is quoted, so parentheses and brackets parse", arguments: [
        ("#elseif os(iOS)", "N0 -->|\"#elseif os(iOS)\"| N1"),
        (".failure(let error)", "N0 -->|\".failure(let error)\"| N1"),
        ("items[0]", "N0 -->|\"items[0]\"| N1")
    ])
    func edgeLabelQuoted(label: String, line: String) {
        #expect(mermaid(edgeLabel: label).contains(line))
    }

    @Test("| is written as Mermaid's #124; entity, in nodes and edges")
    func pipeEscaped() {
        let text = mermaid(edgeLabel: "a | b", nodeLabel: "a || b")
        #expect(text.contains("N0{\"a #124;#124; b\"}"))
        #expect(text.contains("N0 -->|\"a #124; b\"| N1"))
        #expect(!text.contains("&#124;"))
    }
}
