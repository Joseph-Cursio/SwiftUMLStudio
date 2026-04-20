import Testing
@testable import SwiftUMLBridgeFramework

@Suite("ActivitySVGRenderer — layout and rendering")
struct ActivitySVGRendererTests {

    private func straightLineGraph() -> ActivityGraph {
        ActivityGraph(
            nodes: [
                ActivityNode(id: 0, kind: .start, label: ""),
                ActivityNode(id: 1, kind: .action, label: "step1"),
                ActivityNode(id: 2, kind: .action, label: "step2"),
                ActivityNode(id: 3, kind: .end, label: "")
            ],
            edges: [
                ActivityEdge(fromId: 0, toId: 1),
                ActivityEdge(fromId: 1, toId: 2),
                ActivityEdge(fromId: 2, toId: 3)
            ],
            entryType: "Foo", entryMethod: "run"
        )
    }

    @Test("layout assigns rows by longest path from start")
    func longestPathRows() {
        let graph = straightLineGraph()
        let rows = ActivitySVGRenderer.computeRows(graph: graph)
        #expect(rows[0] == 0)
        #expect(rows[1] == 1)
        #expect(rows[2] == 2)
        #expect(rows[3] == 3)
    }

    @Test("columns are symmetric around zero for single-node rows")
    func columnsCentered() {
        let graph = straightLineGraph()
        let rows = ActivitySVGRenderer.computeRows(graph: graph)
        let columns = ActivitySVGRenderer.computeColumns(graph: graph, rows: rows)
        for node in graph.nodes {
            #expect(columns[node.id] == 0)
        }
    }

    @Test("layout totalWidth and totalHeight are non-zero")
    func layoutDimensionsNonZero() {
        let layout = ActivitySVGRenderer.computeLayout(from: straightLineGraph())
        #expect(layout.totalWidth > 0)
        #expect(layout.totalHeight > 0)
    }

    @Test("layout title is Type.method")
    func layoutTitle() {
        let layout = ActivitySVGRenderer.computeLayout(from: straightLineGraph())
        #expect(layout.title == "Foo.run")
    }

    @Test("positioned nodes preserve kind")
    func positionedNodesPreserveKind() {
        let layout = ActivitySVGRenderer.computeLayout(from: straightLineGraph())
        #expect(layout.nodes.first(where: { $0.id == 0 })?.kind == .start)
        #expect(layout.nodes.first(where: { $0.id == 3 })?.kind == .end)
    }

    @Test("back-edges at lower row do not increase target row")
    func backEdgesIgnoredInRowing() {
        let graph = ActivityGraph(
            nodes: [
                ActivityNode(id: 0, kind: .start, label: ""),
                ActivityNode(id: 1, kind: .loopStart, label: "while cond"),
                ActivityNode(id: 2, kind: .action, label: "body"),
                ActivityNode(id: 3, kind: .end, label: "")
            ],
            edges: [
                ActivityEdge(fromId: 0, toId: 1),
                ActivityEdge(fromId: 1, toId: 2, label: "true"),
                ActivityEdge(fromId: 2, toId: 1),
                ActivityEdge(fromId: 1, toId: 3)
            ],
            entryType: "Foo", entryMethod: "run"
        )
        let rows = ActivitySVGRenderer.computeRows(graph: graph)
        #expect(rows[1] == 1)
        #expect(rows[2] == 2)
        #expect(rows[3] == 2)
    }

    @Test("renderFromLayout produces SVG with <svg root and </svg> close")
    func renderedSVGHasRoot() {
        let layout = ActivitySVGRenderer.computeLayout(from: straightLineGraph())
        let svg = ActivitySVGRenderer.renderFromLayout(layout)
        #expect(svg.contains("<svg"))
        #expect(svg.hasSuffix("</svg>"))
    }

    @Test("rendered SVG includes title text")
    func renderedSVGHasTitle() {
        let svg = ActivitySVGRenderer.render(graph: straightLineGraph())
        #expect(svg.contains("Foo.run"))
    }

    @Test("rendered SVG includes arrow marker definition")
    func renderedSVGHasArrowMarker() {
        let svg = ActivitySVGRenderer.render(graph: straightLineGraph())
        #expect(svg.contains("act-arrow"))
    }

    // MARK: - Shape coverage: decision / merge / fork / join

    private func decisionGraph() -> ActivityGraph {
        ActivityGraph(
            nodes: [
                ActivityNode(id: 0, kind: .start, label: ""),
                ActivityNode(id: 1, kind: .decision, label: "flag?"),
                ActivityNode(id: 2, kind: .action, label: "then"),
                ActivityNode(id: 3, kind: .action, label: "else"),
                ActivityNode(id: 4, kind: .merge, label: ""),
                ActivityNode(id: 5, kind: .end, label: "")
            ],
            edges: [
                ActivityEdge(fromId: 0, toId: 1),
                ActivityEdge(fromId: 1, toId: 2, label: "true"),
                ActivityEdge(fromId: 1, toId: 3, label: "false"),
                ActivityEdge(fromId: 2, toId: 4),
                ActivityEdge(fromId: 3, toId: 4),
                ActivityEdge(fromId: 4, toId: 5)
            ],
            entryType: "Foo", entryMethod: "run"
        )
    }

    @Test("decision nodes render as a diamond polygon")
    func decisionRendersDiamond() {
        let svg = ActivitySVGRenderer.render(graph: decisionGraph())
        #expect(svg.contains("<polygon points="))
    }

    @Test("merge nodes render as a diamond polygon")
    func mergeRendersDiamond() {
        let svg = ActivitySVGRenderer.render(graph: decisionGraph())
        // The merge node is a white-filled diamond; filter for the merge fill color.
        #expect(svg.contains("fill=\"#FFFFFF\""))
    }

    @Test("branch labels appear on decision edges")
    func branchLabelsRendered() {
        let svg = ActivitySVGRenderer.render(graph: decisionGraph())
        #expect(svg.contains("true"))
        #expect(svg.contains("false"))
    }

    private func forkJoinGraph() -> ActivityGraph {
        ActivityGraph(
            nodes: [
                ActivityNode(id: 0, kind: .start, label: ""),
                ActivityNode(id: 1, kind: .fork, label: ""),
                ActivityNode(id: 2, kind: .action, label: "task1", isAsync: true),
                ActivityNode(id: 3, kind: .action, label: "task2", isAsync: true),
                ActivityNode(id: 4, kind: .join, label: ""),
                ActivityNode(id: 5, kind: .end, label: "")
            ],
            edges: [
                ActivityEdge(fromId: 0, toId: 1),
                ActivityEdge(fromId: 1, toId: 2),
                ActivityEdge(fromId: 1, toId: 3),
                ActivityEdge(fromId: 2, toId: 4),
                ActivityEdge(fromId: 3, toId: 4),
                ActivityEdge(fromId: 4, toId: 5)
            ],
            entryType: "Foo", entryMethod: "run"
        )
    }

    @Test("fork and join render as horizontal bars")
    func forkJoinRendersBars() {
        let svg = ActivitySVGRenderer.render(graph: forkJoinGraph())
        // Bars have the forkJoin fill; there should be at least two <rect elements with that fill.
        let rectCount = svg.components(separatedBy: "fill=\"#333333\"").count - 1
        #expect(rectCount >= 2)
    }

    @Test("async actions use the async fill color")
    func asyncActionUsesAsyncFill() {
        let svg = ActivitySVGRenderer.render(graph: forkJoinGraph())
        #expect(svg.contains("#EDE7F6"))
    }

    // MARK: - Back-edge coverage

    private func loopGraph() -> ActivityGraph {
        ActivityGraph(
            nodes: [
                ActivityNode(id: 0, kind: .start, label: ""),
                ActivityNode(id: 1, kind: .loopStart, label: "while cond"),
                ActivityNode(id: 2, kind: .action, label: "body"),
                ActivityNode(id: 3, kind: .end, label: "")
            ],
            edges: [
                ActivityEdge(fromId: 0, toId: 1),
                ActivityEdge(fromId: 1, toId: 2, label: "true"),
                ActivityEdge(fromId: 2, toId: 1),
                ActivityEdge(fromId: 1, toId: 3)
            ],
            entryType: "Foo", entryMethod: "run"
        )
    }

    @Test("loop back-edges render as a dashed path")
    func backEdgeIsDashed() {
        let svg = ActivitySVGRenderer.render(graph: loopGraph())
        #expect(svg.contains("stroke-dasharray=\"4,3\""))
        #expect(svg.contains("<path d="))
    }

    @Test("loopStart renders as a diamond")
    func loopStartRendersDiamond() {
        let svg = ActivitySVGRenderer.render(graph: loopGraph())
        #expect(svg.contains("<polygon points="))
    }
}
