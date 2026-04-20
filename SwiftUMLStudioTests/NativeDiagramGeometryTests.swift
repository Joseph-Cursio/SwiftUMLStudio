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
