import Testing
@testable import SwiftUMLBridgeFramework

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
            DependencyEdge(from: "A", to: "B", kind: .conforms),
            DependencyEdge(from: "B", to: "C", kind: .conforms)
        ]
        let model = DependencyGraphModel(edges: edges)
        #expect(model.detectCycles().isEmpty)
    }

    @Test("star topology (no cycles) has no cycles")
    func starTopologyNoCycles() {
        let edges = [
            DependencyEdge(from: "Core", to: "A", kind: .imports),
            DependencyEdge(from: "Core", to: "B", kind: .imports),
            DependencyEdge(from: "Core", to: "C", kind: .imports)
        ]
        let model = DependencyGraphModel(edges: edges)
        #expect(model.detectCycles().isEmpty)
    }

    // MARK: - Cycle detection: direct cycles

    @Test("direct cycle A→B→A marks both nodes")
    func directCycleMarksBothNodes() {
        let edges = [
            DependencyEdge(from: "A", to: "B", kind: .conforms),
            DependencyEdge(from: "B", to: "A", kind: .conforms)
        ]
        let model = DependencyGraphModel(edges: edges)
        let cycles = model.detectCycles()
        #expect(cycles.contains("A"))
        #expect(cycles.contains("B"))
    }

    @Test("self-cycle marks the node")
    func selfCycleMarksNode() {
        let edges = [
            DependencyEdge(from: "Recursive", to: "Recursive", kind: .imports)
        ]
        let model = DependencyGraphModel(edges: edges)
        let cycles = model.detectCycles()
        #expect(cycles.contains("Recursive"))
    }

    // MARK: - Cycle detection: transitive cycles

    @Test("transitive cycle A→B→C→A marks all three nodes")
    func transitiveCycleMarksAllNodes() {
        let edges = [
            DependencyEdge(from: "A", to: "B", kind: .imports),
            DependencyEdge(from: "B", to: "C", kind: .imports),
            DependencyEdge(from: "C", to: "A", kind: .imports)
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
            DependencyEdge(from: "D", to: "A", kind: .imports),
            DependencyEdge(from: "A", to: "B", kind: .imports),
            DependencyEdge(from: "B", to: "C", kind: .imports),
            DependencyEdge(from: "C", to: "B", kind: .imports)
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
        DependencyEdge(from: "Canvas", to: "Drawable", kind: .inherits),
        DependencyEdge(from: "Canvas", to: "Themed", kind: .inherits),
        DependencyEdge(from: "Drawable", to: "Paintable", kind: .conforms),
        DependencyEdge(from: "Paintable", to: "Canvas", kind: .conforms),
        DependencyEdge(from: "Themed", to: "Paintable", kind: .conforms)
    ]

    /// The same for `class Node: Visible, Styled {}`, `protocol Visible: Rooted, Framed {}`,
    /// `protocol Rooted: Node {}`, `protocol Styled: Visible {}` and `protocol Framed: Rooted {}`.
    /// Every start node missed at least one member.
    static let node = [
        DependencyEdge(from: "Node", to: "Visible", kind: .inherits),
        DependencyEdge(from: "Node", to: "Styled", kind: .inherits),
        DependencyEdge(from: "Visible", to: "Rooted", kind: .conforms),
        DependencyEdge(from: "Visible", to: "Framed", kind: .conforms),
        DependencyEdge(from: "Rooted", to: "Node", kind: .conforms),
        DependencyEdge(from: "Styled", to: "Visible", kind: .conforms),
        DependencyEdge(from: "Framed", to: "Rooted", kind: .conforms)
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
        let edges = [DependencyEdge(from: "Button", to: "Canvas", kind: .inherits)] + Self.canvas
            + [DependencyEdge(from: "Paintable", to: "AnyObject", kind: .conforms)]
        #expect(results(edges) == [["Canvas", "Drawable", "Paintable", "Themed"]])
    }

    @Test("an edge from a node to itself puts only that node on a cycle")
    func selfLoopOnly() {
        let edges = [
            DependencyEdge(from: "Core", to: "Core", kind: .imports),
            DependencyEdge(from: "Core", to: "Foundation", kind: .imports)
        ]
        #expect(results(edges) == [["Core"]])
    }

    @Test("two separate cycles are both found")
    func twoCycles() {
        let edges = [
            DependencyEdge(from: "A", to: "B", kind: .imports),
            DependencyEdge(from: "B", to: "A", kind: .imports),
            DependencyEdge(from: "B", to: "C", kind: .imports),
            DependencyEdge(from: "C", to: "D", kind: .imports),
            DependencyEdge(from: "D", to: "C", kind: .imports)
        ]
        #expect(results(edges) == [["A", "B", "C", "D"]])
    }

    // MARK: - edges property

    @Test("model exposes edges")
    func modelExposesEdges() {
        let edges = [
            DependencyEdge(from: "Foo", to: "Bar", kind: .inherits),
            DependencyEdge(from: "Bar", to: "Baz", kind: .conforms)
        ]
        let model = DependencyGraphModel(edges: edges)
        #expect(model.edges.count == 2)
    }
}
