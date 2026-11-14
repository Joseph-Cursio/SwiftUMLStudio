@testable import SwiftUMLBridgeFramework
import Testing

@Suite("DependencyGraphModel")
struct DependencyGraphModelTests {

    // MARK: - Cycle detection: no cycles

    @Test("empty graph has no cycles")
    func emptyCycles() {
        let model = DependencyGraphModel(edges: [])
        #expect(model.detectCycles().isEmpty)
    }

    @Test("linear chain has no cycles")
    func linearChainNoCycles() {
        let edges = [
            DependencyEdge(from: "A", toNode: "B", kind: .conforms),
            DependencyEdge(from: "B", toNode: "C", kind: .conforms),
        ]
        let model = DependencyGraphModel(edges: edges)
        #expect(model.detectCycles().isEmpty)
    }

    @Test("star topology (no cycles) has no cycles")
    func starTopologyNoCycles() {
        let edges = [
            DependencyEdge(from: "Core", toNode: "A", kind: .imports),
            DependencyEdge(from: "Core", toNode: "B", kind: .imports),
            DependencyEdge(from: "Core", toNode: "C", kind: .imports),
        ]
        let model = DependencyGraphModel(edges: edges)
        #expect(model.detectCycles().isEmpty)
    }

    // MARK: - Cycle detection: direct cycles

    @Test("direct cycle A→B→A marks both nodes")
    func directCycleMarksBothNodes() {
        let edges = [
            DependencyEdge(from: "A", toNode: "B", kind: .conforms),
            DependencyEdge(from: "B", toNode: "A", kind: .conforms),
        ]
        let model = DependencyGraphModel(edges: edges)
        let cycles = model.detectCycles()
        #expect(cycles.contains("A"))
        #expect(cycles.contains("B"))
    }

    @Test("self-cycle marks the node")
    func selfCycleMarksNode() {
        let edges = [
            DependencyEdge(from: "Recursive", toNode: "Recursive", kind: .imports)
        ]
        let model = DependencyGraphModel(edges: edges)
        let cycles = model.detectCycles()
        #expect(cycles.contains("Recursive"))
    }

    // MARK: - Cycle detection: transitive cycles

    @Test("transitive cycle A→B→C→A marks all three nodes")
    func transitiveCycleMarksAllNodes() {
        let edges = [
            DependencyEdge(from: "A", toNode: "B", kind: .imports),
            DependencyEdge(from: "B", toNode: "C", kind: .imports),
            DependencyEdge(from: "C", toNode: "A", kind: .imports),
        ]
        let model = DependencyGraphModel(edges: edges)
        let cycles = model.detectCycles()
        #expect(cycles.contains("A"))
        #expect(cycles.contains("B"))
        #expect(cycles.contains("C"))
    }

    @Test("node not in cycle is not reported")
    func nodeNotInCycleNotReported() {
        // D → A → B → C → A (cycle: A,B,C; D feeds into cycle but is not in it)
        let edges = [
            DependencyEdge(from: "D", toNode: "A", kind: .imports),
            DependencyEdge(from: "A", toNode: "B", kind: .imports),
            DependencyEdge(from: "B", toNode: "C", kind: .imports),
            DependencyEdge(from: "C", toNode: "B", kind: .imports),
        ]
        let model = DependencyGraphModel(edges: edges)
        let cycles = model.detectCycles()
        // B and C are in a cycle; D and A feed into the cycle but are not in it
        #expect(cycles.contains("B"))
        #expect(cycles.contains("C"))
        #expect(cycles.contains("D") == false)
    }

    // MARK: - Cycle detection: every member, wherever the search starts (#143)

    /// The edges `deps --types` lists for `class Canvas: Drawable, Themed {}`,
    /// `protocol Drawable: Paintable {}`, `protocol Paintable: Canvas {}` and
    /// `protocol Themed: Paintable {}`. A search that reached `Themed` after `Paintable` was
    /// finished left `Themed` out.
    static let canvas = [
        DependencyEdge(from: "Canvas", toNode: "Drawable", kind: .inherits),
        DependencyEdge(from: "Canvas", toNode: "Themed", kind: .inherits),
        DependencyEdge(from: "Drawable", toNode: "Paintable", kind: .conforms),
        DependencyEdge(from: "Paintable", toNode: "Canvas", kind: .conforms),
        DependencyEdge(from: "Themed", toNode: "Paintable", kind: .conforms),
    ]

    /// The same for `class Node: Visible, Styled {}`, `protocol Visible: Rooted, Framed {}`,
    /// `protocol Rooted: Node {}`, `protocol Styled: Visible {}` and `protocol Framed: Rooted {}`.
    /// Every start node missed at least one member.
    static let node = [
        DependencyEdge(from: "Node", toNode: "Visible", kind: .inherits),
        DependencyEdge(from: "Node", toNode: "Styled", kind: .inherits),
        DependencyEdge(from: "Visible", toNode: "Rooted", kind: .conforms),
        DependencyEdge(from: "Visible", toNode: "Framed", kind: .conforms),
        DependencyEdge(from: "Rooted", toNode: "Node", kind: .conforms),
        DependencyEdge(from: "Styled", toNode: "Visible", kind: .conforms),
        DependencyEdge(from: "Framed", toNode: "Rooted", kind: .conforms),
    ]

    private func results(_ edges: [DependencyEdge], calls: Int = 50) -> Set<[String]> {
        Set((0..<calls).map { _ in DependencyGraphModel(edges: edges).detectCycles().sorted() })
    }

    @Test("a node reached through a finished part of the cycle is still on it")
    func canvasCycle() {
        #expect(results(Self.canvas) == [["Canvas", "Drawable", "Paintable", "Themed"]])
    }

    @Test("every node of a cycle with several back edges is on it")
    func nodeCycle() {
        #expect(results(Self.node) == [["Framed", "Node", "Rooted", "Styled", "Visible"]])
    }

    @Test("a node that only leads into a cycle, or is only reached from one, is not on it")
    func feedersAreNotMembers() {
        let edges = [DependencyEdge(from: "Button", toNode: "Canvas", kind: .inherits)] + Self.canvas
            + [DependencyEdge(from: "Paintable", toNode: "AnyObject", kind: .conforms)]
        #expect(results(edges) == [["Canvas", "Drawable", "Paintable", "Themed"]])
    }

    @Test("an edge from a node to itself puts only that node on a cycle")
    func selfLoopOnly() {
        let edges = [
            DependencyEdge(from: "Core", toNode: "Core", kind: .imports),
            DependencyEdge(from: "Core", toNode: "Foundation", kind: .imports),
        ]
        #expect(results(edges) == [["Core"]])
    }

    @Test("two separate cycles are both found")
    func twoCycles() {
        let edges = [
            DependencyEdge(from: "A", toNode: "B", kind: .imports),
            DependencyEdge(from: "B", toNode: "A", kind: .imports),
            DependencyEdge(from: "B", toNode: "C", kind: .imports),
            DependencyEdge(from: "C", toNode: "D", kind: .imports),
            DependencyEdge(from: "D", toNode: "C", kind: .imports),
        ]
        #expect(results(edges) == [["A", "B", "C", "D"]])
    }

    // MARK: - edges property

    @Test("model exposes edges")
    func modelExposesEdges() {
        let edges = [
            DependencyEdge(from: "Foo", toNode: "Bar", kind: .inherits),
            DependencyEdge(from: "Bar", toNode: "Baz", kind: .conforms),
        ]
        let model = DependencyGraphModel(edges: edges)
        #expect(model.edges.count == 2)
    }
}
