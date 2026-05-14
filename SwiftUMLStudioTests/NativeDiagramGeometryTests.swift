import CoreGraphics
import Foundation
import SwiftUI
import Testing
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio

@Suite("NativeDiagramGeometry.headerColor")
struct NativeDiagramGeometryHeaderColorTests {

    @Test("every known stereotype resolves to a distinct color")
    func knownStereotypes() {
        let keys = ["class", "struct", "enum", "protocol", "actor", "extension", "macro", "warning"]
        for key in keys {
            _ = NativeDiagramGeometry.headerColor(for: key)
        }
        #expect(NativeDiagramGeometry.headerColors.count == keys.count)
    }

    @Test("unknown stereotype falls back to the class color")
    func unknownFallback() {
        let fallback = NativeDiagramGeometry.headerColor(for: "unknown-kind")
        #expect(fallback == NativeDiagramGeometry.headerColors["class"])
    }

    @Test("nil stereotype falls back to the class color")
    func nilStereotype() {
        #expect(
            NativeDiagramGeometry.headerColor(for: nil) == NativeDiagramGeometry.headerColors["class"]
        )
    }
}

@Suite("NativeDiagramGeometry.moduleColor")
struct NativeDiagramGeometryModuleColorTests {

    @Test("returns the same color for the same module name")
    func deterministic() {
        let first = NativeDiagramGeometry.moduleColor(for: "Networking")
        let second = NativeDiagramGeometry.moduleColor(for: "Networking")
        #expect(first == second)
    }

    @Test("different modules generally get different colors")
    func variesAcrossModules() {
        let networking = NativeDiagramGeometry.moduleColor(for: "Networking")
        let ui = NativeDiagramGeometry.moduleColor(for: "UI")
        #expect(networking != ui)
    }
}

@Suite("NativeDiagramGeometry.nodeRect + headerRect")
struct NativeDiagramGeometryNodeRectTests {

    private func makeNode(
        posX: Double = 100, posY: Double = 200,
        width: Double = 80, height: Double = 60
    ) -> LayoutNode {
        var node = LayoutNode(id: "n", label: "", stereotype: nil, compartments: [])
        node.posX = posX
        node.posY = posY
        node.width = width
        node.height = height
        return node
    }

    @Test("nodeRect is centered on posX/posY")
    func nodeRectCentered() {
        let rect = NativeDiagramGeometry.nodeRect(for: makeNode())
        #expect(rect.midX == 100)
        #expect(rect.midY == 200)
        #expect(rect.width == 80)
        #expect(rect.height == 60)
    }

    @Test("headerRect clamps to the node height when the node is shorter than the header band")
    func headerClampsForSmallNodes() {
        let rect = NativeDiagramGeometry.headerRect(for: makeNode(height: 20))
        #expect(rect.height == 20)
    }

    @Test("headerRect uses the default header height for tall-enough nodes")
    func headerUsesDefault() {
        let rect = NativeDiagramGeometry.headerRect(for: makeNode(height: 120))
        #expect(rect.height == NativeDiagramGeometry.headerHeight)
    }

    @Test("clusterRect is centered on the cluster's posX/posY")
    func clusterRectCentered() {
        var cluster = LayoutCluster(id: "Core", label: "Core")
        cluster.posX = 300
        cluster.posY = 250
        cluster.width = 400
        cluster.height = 320
        let rect = NativeDiagramGeometry.clusterRect(for: cluster)
        #expect(rect.midX == 300)
        #expect(rect.midY == 250)
        #expect(rect.width == 400)
        #expect(rect.height == 320)
    }
}

@Suite("NativeDiagramGeometry.strokeStyle")
struct NativeDiagramGeometryStrokeStyleTests {

    @Test("realization is dashed")
    func realizationDashed() {
        let style = NativeDiagramGeometry.strokeStyle(for: .realization)
        #expect(style.dash == [6, 3])
    }

    @Test("dependency is dashed")
    func dependencyDashed() {
        let style = NativeDiagramGeometry.strokeStyle(for: .dependency)
        #expect(style.dash == [6, 3])
    }

    @Test("inheritance is solid")
    func inheritanceSolid() {
        let style = NativeDiagramGeometry.strokeStyle(for: .inheritance)
        #expect(style.dash.isEmpty)
    }

    @Test("composition and association are solid")
    func othersSolid() {
        #expect(NativeDiagramGeometry.strokeStyle(for: .composition).dash.isEmpty)
        #expect(NativeDiagramGeometry.strokeStyle(for: .association).dash.isEmpty)
    }
}

@Suite("NativeDiagramGeometry.arrowheadPoints")
struct NativeDiagramGeometryArrowheadTests {

    @Test("rightward arrow produces points to the left of the tip")
    func rightwardArrow() {
        let tip = CGPoint(x: 100, y: 50)
        let prev = CGPoint(x: 0, y: 50)
        let points = NativeDiagramGeometry.arrowheadPoints(tip: tip, prev: prev)
        // Both base points should be behind the tip (smaller x than the tip).
        #expect(points.left.x < tip.x)
        #expect(points.right.x < tip.x)
        // The two base vertices straddle the tip's horizontal line.
        #expect(points.left.y != points.right.y)
        #expect(min(points.left.y, points.right.y) < tip.y)
        #expect(max(points.left.y, points.right.y) > tip.y)
    }

    @Test("downward arrow produces points above the tip")
    func downwardArrow() {
        let tip = CGPoint(x: 50, y: 100)
        let prev = CGPoint(x: 50, y: 0)
        let points = NativeDiagramGeometry.arrowheadPoints(tip: tip, prev: prev)
        #expect(points.left.y < tip.y)
        #expect(points.right.y < tip.y)
    }
}

@Suite("NativeDiagramGeometry.diamondPoints")
struct NativeDiagramGeometryDiamondTests {

    @Test("rightward diamond has mid and far behind the tip")
    func rightwardDiamond() {
        let tip = CGPoint(x: 100, y: 50)
        let points = NativeDiagramGeometry.diamondPoints(tip: tip, angle: 0, length: 12, width: 6)
        #expect(points.tip == tip)
        #expect(points.mid.x < tip.x, "mid should be back along the edge")
        #expect(points.far.x < points.mid.x, "far should be further back than mid")
    }

    @Test("left and right vertices are reflected across the tip-far axis")
    func diamondVerticesSymmetric() {
        let tip = CGPoint(x: 100, y: 50)
        let points = NativeDiagramGeometry.diamondPoints(tip: tip, angle: 0, length: 12, width: 6)
        #expect(abs(points.left.y - points.mid.y - 6) < 1e-9
                || abs(points.right.y - points.mid.y - 6) < 1e-9)
        // The y-midpoint of left+right lies on the tip axis (y = 50).
        let midY = (points.left.y + points.right.y) / 2
        #expect(abs(midY - 50) < 1e-9)
    }
}

@Suite("NativeDiagramGeometry.hitNode")
struct NativeDiagramGeometryHitNodeTests {

    private func makeNode(
        id: String, posX: Double, posY: Double,
        width: Double = 80, height: Double = 60
    ) -> LayoutNode {
        var node = LayoutNode(id: id, label: id)
        node.posX = posX
        node.posY = posY
        node.width = width
        node.height = height
        return node
    }

    @Test("returns the node whose rect contains the point")
    func hitsTheCorrectNode() throws {
        let nodeA = makeNode(id: "A", posX: 100, posY: 100)
        let nodeB = makeNode(id: "B", posX: 300, posY: 100)
        let graph = LayoutGraph(nodes: [nodeA, nodeB])

        let hit = try #require(NativeDiagramGeometry.hitNode(in: graph, at: CGPoint(x: 110, y: 105)))
        #expect(hit.id == "A")
    }

    @Test("returns nil when the point is on the background")
    func missesEmptySpace() {
        let node = makeNode(id: "A", posX: 100, posY: 100)
        let graph = LayoutGraph(nodes: [node])
        #expect(NativeDiagramGeometry.hitNode(in: graph, at: CGPoint(x: 500, y: 500)) == nil)
    }

    @Test("the topmost (last-drawn) node wins when bounds overlap")
    func topmostNodeWinsOnOverlap() throws {
        let lower = makeNode(id: "lower", posX: 100, posY: 100)
        let upper = makeNode(id: "upper", posX: 110, posY: 110)
        let graph = LayoutGraph(nodes: [lower, upper])

        let hit = try #require(
            NativeDiagramGeometry.hitNode(in: graph, at: CGPoint(x: 100, y: 100))
        )
        #expect(hit.id == "upper")
    }

    @Test("a point on the rect edge counts as a hit")
    func edgeCountsAsHit() throws {
        let node = makeNode(id: "A", posX: 100, posY: 100, width: 80, height: 60)
        let graph = LayoutGraph(nodes: [node])
        // node rect is x: 60...140, y: 70...130
        let hit = try #require(
            NativeDiagramGeometry.hitNode(in: graph, at: CGPoint(x: 60, y: 70))
        )
        #expect(hit.id == "A")
    }

    @Test("returns nil for an empty graph")
    func emptyGraph() {
        #expect(NativeDiagramGeometry.hitNode(in: LayoutGraph(), at: CGPoint(x: 0, y: 0)) == nil)
    }
}

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
            ("G", 0.0, 200.0), ("H", 100.0, 200.0), ("I", 200.0, 200.0)
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
            NativeDiagramGeometry.nextNode(in: gridGraph(), from: "E", direction: .up)
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
        #expect(NativeDiagramGeometry.nextNode(in: gridGraph(), from: "A", direction: .up) == nil)
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
