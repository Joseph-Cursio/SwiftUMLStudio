import CoreGraphics
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio
import Testing

@Suite("NativeDiagramGeometry.hitNode")
struct NativeDiagramGeometryHitNodeTests {

    private func makeNode(
        id: String,
        posX: Double,
        posY: Double,
        width: Double = 80,
        height: Double = 60
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
        #expect(NativeDiagramGeometry.hitNode(in: LayoutGraph(), at: CGPoint.zero) == nil)
    }
}
