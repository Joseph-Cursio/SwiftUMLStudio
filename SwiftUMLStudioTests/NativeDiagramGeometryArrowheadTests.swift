import CoreGraphics
@testable import SwiftUMLStudio
import Testing

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
