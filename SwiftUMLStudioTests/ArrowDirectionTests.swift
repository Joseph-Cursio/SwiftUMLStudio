@testable import SwiftUMLStudio
import Testing

@Suite("NativeSequenceGeometry arrow direction and label midpoint")
struct ArrowDirectionTests {

    @Test("toX less than fromX points left")
    func pointsLeft() {
        #expect(NativeSequenceGeometry.arrowPointsLeft(from: 200, toX: 100))
    }

    @Test("toX greater than fromX points right")
    func pointsRight() {
        #expect(NativeSequenceGeometry.arrowPointsLeft(from: 100, toX: 200) == false)
    }

    @Test("label midpoint is the simple mean")
    func labelMid() {
        #expect(NativeSequenceGeometry.labelMidX(from: 100, toX: 300) == 200)
    }
}
