import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// graphre.js recurses once per rank (`initOrder`) and once per level of its spanning tree
/// (`dfsAssignLowLim`), inside JavaScriptCore, which gives a script no more stack than the thread
/// it runs on. The layout ran on whatever thread called `DagreLayoutEngine.layout`, so on the
/// 512 KB cooperative threads Swift Testing, the CLI and Studio's detached tasks use, a chain of
/// 660 classes or a zigzag of 893 structs made the script throw, and the engine quietly drew its
/// grid instead (#150). Each test checks the geometry, since the grid keeps every node and edge.
@Suite("The dagre layout holds a long graph on a cooperative thread")
struct DagreLayoutDepthTests {
    static let length = 1_000

    /// `class C<i>: C<i-1>`, as `LayoutGraphBuilder` draws it: an edge from each class to its parent.
    static func chain(_ length: Int) -> LayoutGraph {
        LayoutGraph(
            nodes: (0..<length).map { LayoutNode(id: "C\($0)", label: "C\($0)") },
            edges: (1..<length).map { LayoutEdge(sourceId: "C\($0)", targetId: "C\($0 - 1)", style: .inheritance) }
        )
    }

    /// `protocol P0 … P<n>`, then `struct S<i>: P<i>, P<i+1>`: two ranks, one long undirected path.
    static func zigzag(_ structs: Int) -> LayoutGraph {
        let protocols = (0...structs).map { LayoutNode(id: "P\($0)", label: "P\($0)") }
        let types = (0..<structs).map { LayoutNode(id: "S\($0)", label: "S\($0)") }
        let edges = (0..<structs).flatMap { index in
            [LayoutEdge(sourceId: "S\(index)", targetId: "P\(index)", style: .realization),
             LayoutEdge(sourceId: "S\(index)", targetId: "P\(index + 1)", style: .realization)]
        }
        return LayoutGraph(nodes: protocols + types, edges: edges)
    }

    /// The other tests show the fix only on a stack this small. On a big thread they would pass
    /// either way. The main thread reports 512 KB here but has 8 MB, so it is ruled out too.
    @Test("these tests run on a stack small enough that the layout overflowed it")
    func smallStack() {
        #expect(Thread.current.stackSize <= 1 << 20)
        #expect(!Thread.isMainThread)
    }

    /// Dagre puts a chain in one column, one class per rank. The grid puts it in ⌈√n⌉ columns.
    @Test("a long chain of classes is laid out by dagre, one class per rank")
    func chainLayout() {
        let laid = DagreLayoutEngine.layout(Self.chain(Self.length))
        #expect(Set(laid.nodes.map(\.posX)).count == 1)
        #expect(Set(laid.nodes.map(\.posY)).count == Self.length)
    }

    @Test("a long zigzag of structs and protocols is laid out by dagre on two ranks")
    func zigzagLayout() {
        let laid = DagreLayoutEngine.layout(Self.zigzag(Self.length))
        #expect(Set(laid.nodes.map(\.posY)).count == 2)
    }

    @Test("a long chain is laid out by dagre in a detached task, as Studio generates")
    func chainInDetachedTask() async {
        let columns = await Task.detached(priority: .userInitiated) {
            Set(DagreLayoutEngine.layout(Self.chain(Self.length)).nodes.map(\.posX)).count
        }.value
        #expect(columns == 1)
    }

    @Test("an SVG class diagram of a long chain from source is one column")
    func classDiagramFromSource() throws {
        let source = (["class C0 {}"] + (1..<Self.length).map { "class C\($0): C\($0 - 1) {}" })
            .joined(separator: "\n")
        let script = ClassDiagramGenerator().generateScript(for: source, with: Configuration(format: .svg))
        let graph = try #require(script.layoutGraph)
        #expect(graph.nodes.count == Self.length)
        #expect(Set(graph.nodes.map(\.posX)).count == 1)
    }

    /// `layoutOnThisThread` is the layout without the big thread, so on this one it throws, as
    /// `layout` did before. The grid then says why, for the CLI and Studio to pass on.
    @Test("a layout that throws says what it threw")
    func fallbackReason() {
        let laid = DagreLayoutEngine.layoutOnThisThread(Self.chain(Self.length))
        #expect(laid.fallbackReason == "RangeError: Maximum call stack size exceeded.")
        #expect(DagreLayoutEngine.layout(Self.chain(Self.length)).fallbackReason == nil)
    }
}
