import CoreGraphics
import Foundation
import SwiftUI
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio
import Testing

@Suite("NativeDiagramGeometry.nextNode (arrow navigation)")
struct NativeDiagramGeometryNextNodeTests {

    private func makeNode(id: String, posX: Double, posY: Double) -> LayoutNode {
        var node = LayoutNode(id: id, label: id)
        node.posX = posX
        node.posY = posY
        node.width = 80
        node.height = 60
        return node
    }

    /// Layout:
    ///   A B C
    ///   D E F
    ///   G H I
    /// (3x3 grid, 100pt apart)
    private func gridGraph() -> LayoutGraph {
        let nodes = [
            ("A", 0.0, 0.0), ("B", 100.0, 0.0), ("C", 200.0, 0.0),
            ("D", 0.0, 100.0), ("E", 100.0, 100.0), ("F", 200.0, 100.0),
            ("G", 0.0, 200.0), ("H", 100.0, 200.0), ("I", 200.0, 200.0),
        ].map { makeNode(id: $0.0, posX: $0.1, posY: $0.2) }
        return LayoutGraph(nodes: nodes)
    }

    @Test("right from E selects F")
    func rightFromCenter() throws {
        let next = try #require(
            NativeDiagramGeometry.nextNode(in: gridGraph(), from: "E", direction: .right)
        )
        #expect(next.id == "F")
    }

    @Test("left from E selects D")
    func leftFromCenter() throws {
        let next = try #require(
            NativeDiagramGeometry.nextNode(in: gridGraph(), from: "E", direction: .left)
        )
        #expect(next.id == "D")
    }

    @Test("up from E selects B")
    func upFromCenter() throws {
        let next = try #require(
            NativeDiagramGeometry.nextNode(in: gridGraph(), from: "E", direction: .upward)
        )
        #expect(next.id == "B")
    }

    @Test("down from E selects H")
    func downFromCenter() throws {
        let next = try #require(
            NativeDiagramGeometry.nextNode(in: gridGraph(), from: "E", direction: .down)
        )
        #expect(next.id == "H")
    }

    @Test("right from C (right-edge node) returns nil")
    func rightFromRightEdge() {
        #expect(NativeDiagramGeometry.nextNode(in: gridGraph(), from: "C", direction: .right) == nil)
    }

    @Test("up from A (top-left node) returns nil")
    func upFromTopLeft() {
        #expect(NativeDiagramGeometry.nextNode(in: gridGraph(), from: "A", direction: .upward) == nil)
    }

    @Test("nextNode for a missing currentId returns nil")
    func unknownIdReturnsNil() {
        #expect(NativeDiagramGeometry.nextNode(in: gridGraph(), from: "Z", direction: .right) == nil)
    }

    @Test("firstNode picks the topmost-leftmost node")
    func firstNodePicksTopLeft() throws {
        let first = try #require(NativeDiagramGeometry.firstNode(in: gridGraph()))
        #expect(first.id == "A")
    }

    @Test("firstNode returns nil for an empty graph")
    func firstNodeEmptyGraph() {
        #expect(NativeDiagramGeometry.firstNode(in: LayoutGraph()) == nil)
    }
}
