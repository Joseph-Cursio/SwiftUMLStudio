import CoreGraphics
@testable import SwiftUMLStudio
import Testing

@Suite("NativeSequenceGeometry.selfLoop")
struct SelfLoopGeometryTests {

    @Test("loop anchors form an ⟲ rectangle and label sits to the right")
    func loopShape() {
        let loop = NativeSequenceGeometry.selfLoop(at: 100, posY: 50)
        #expect(loop.start == CGPoint(x: 100, y: 50))
        #expect(loop.top == CGPoint(x: 130, y: 50))
        #expect(loop.bottom == CGPoint(x: 130, y: 70))
        #expect(loop.returnPoint == CGPoint(x: 100, y: 70))
        #expect(loop.labelOrigin.x > loop.top.x, "label should be to the right of the loop")
        #expect(loop.labelOrigin.y == 60, "label sits at the vertical midpoint of the loop")
    }
}
