import CoreGraphics
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio
import Testing

@Suite("NativeDiagramGeometry.nodeRect + headerRect")
struct NativeDiagramGeometryNodeRectTests {

    private func makeNode(
        posX: Double = 100,
        posY: Double = 200,
        width: Double = 80,
        height: Double = 60
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
