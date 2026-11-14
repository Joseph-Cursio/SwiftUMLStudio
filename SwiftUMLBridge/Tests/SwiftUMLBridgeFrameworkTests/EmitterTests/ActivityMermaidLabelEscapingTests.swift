@testable import SwiftUMLBridgeFramework
import Testing

/// Mermaid 11 rejects a `(` or `[` in a bare edge label, and with it the whole diagram, and reads
/// `#124;` inside `&#124;` so that `|` was drawn `&|`.
@Suite("Activity Mermaid label escaping")
struct ActivityMermaidLabelEscapingTests {

    private func mermaid(edgeLabel: String, nodeLabel: String = "cond?") -> String {
        let graph = ActivityGraph(
            nodes: [
                ActivityNode(id: 0, kind: .decision, label: nodeLabel),
                ActivityNode(id: 1, kind: .action, label: "next"),
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
        ("items[0]", "N0 -->|\"items[0]\"| N1"),
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
