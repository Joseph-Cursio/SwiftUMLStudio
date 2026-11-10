import CoreGraphics
import Foundation
import SwiftUI
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio
import Testing

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
