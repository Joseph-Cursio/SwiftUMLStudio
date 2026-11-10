import CoreGraphics
@testable import SwiftUMLStudio
import Testing

@Suite("NativeSequenceGeometry.smallArrowPoints")
struct SmallArrowPointsTests {

    @Test("pointing left produces base vertices to the right of the tip")
    func pointingLeft() {
        let points = NativeSequenceGeometry.smallArrowPoints(
            at: CGPoint(x: 100, y: 50), pointingLeft: true
        )
        #expect(points.tip == CGPoint(x: 100, y: 50))
        #expect(points.upper.x > 100)
        #expect(points.lower.x > 100)
        #expect(points.upper.y < 50)
        #expect(points.lower.y > 50)
    }

    @Test("pointing right produces base vertices to the left of the tip")
    func pointingRight() {
        let points = NativeSequenceGeometry.smallArrowPoints(
            at: CGPoint(x: 100, y: 50), pointingLeft: false
        )
        #expect(points.upper.x < 100)
        #expect(points.lower.x < 100)
    }
}
