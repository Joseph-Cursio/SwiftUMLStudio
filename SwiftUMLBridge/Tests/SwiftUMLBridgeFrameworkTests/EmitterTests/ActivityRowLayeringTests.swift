import Testing
@testable import SwiftUMLBridgeFramework

@Suite("ActivitySVGRenderer — longest-path rows on extracted graphs")
struct ActivityRowLayeringTests {

    static let source = """
    struct S {
        func ifThenJoin(c: Bool) {
            if c { a1(); a2() }
            done()
        }
        func unevenElse(c: Bool) {
            if c { a1() } else { b1(); b2() }
            done()
        }
        func guardReturn(c: Bool) {
            guard c else { log(); return }
            work()
        }
        func bothBranchesReturn(c: Bool) -> Int {
            if c { return 1 } else { return 2 }
        }
        func deadLoopAfterReturn(c: Bool) {
            step()
            return
            while c { spin() }
        }
        func whileLoop(c: Bool) {
            while c { a1(); a2() }
            done()
        }
    }
    """

    private func graph(_ method: String) throws -> ActivityGraph {
        try #require(
            ActivityFlowExtractor.extract(from: Self.source, entryType: "S", entryMethod: method)
        )
    }

    // None of these bodies has a loop, so every edge is a forward edge.
    @Test("a join sits below every predecessor in a loop-free body",
          arguments: ["ifThenJoin", "unevenElse", "guardReturn", "bothBranchesReturn"])
    func everyEdgeDescends(method: String) throws {
        let graph = try graph(method)
        let rows = ActivitySVGRenderer.computeRows(graph: graph)
        for edge in graph.edges {
            let fromRow = try #require(rows[edge.fromId])
            let toRow = try #require(rows[edge.toId])
            #expect(toRow > fromRow, "\(method): \(edge.fromId)->\(edge.toId) goes row \(fromRow) -> \(toRow)")
        }
        #expect(!ActivitySVGRenderer.render(graph: graph).contains("stroke-dasharray"))
    }

    @Test("a cycle that start never reaches does not stall layering")
    func deadLoopIsIgnored() throws {
        let graph = try graph("deadLoopAfterReturn")
        let rows = ActivitySVGRenderer.computeRows(graph: graph)
        let end = try #require(graph.nodes.first { $0.kind == .end })
        let returnNode = try #require(graph.nodes.first { $0.label == "return" })
        let endRow = try #require(rows[end.id])
        let returnRow = try #require(rows[returnNode.id])
        #expect(endRow > returnRow)
    }

    @Test("a while loop renders exactly one dashed back-edge")
    func whileLoopHasOneBackEdge() throws {
        let graph = try graph("whileLoop")
        let svg = ActivitySVGRenderer.render(graph: graph)
        #expect(svg.components(separatedBy: "stroke-dasharray").count - 1 == 1)
    }

    @Test("forwardEdges drops self-loops and edges closing a cycle")
    func forwardEdgesDropsBackEdges() {
        let edges = [
            ActivityEdge(fromId: 0, toId: 1),
            ActivityEdge(fromId: 1, toId: 1),
            ActivityEdge(fromId: 1, toId: 2),
            ActivityEdge(fromId: 2, toId: 1),
            ActivityEdge(fromId: 1, toId: 3),
            ActivityEdge(fromId: 4, toId: 3)
        ]
        let forward = ActivitySVGRenderer.forwardEdges(from: 0, in: edges)
        #expect(forward == [
            ActivityEdge(fromId: 0, toId: 1),
            ActivityEdge(fromId: 1, toId: 2),
            ActivityEdge(fromId: 1, toId: 3)
        ])
    }
}
