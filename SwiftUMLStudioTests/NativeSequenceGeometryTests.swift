import CoreGraphics
import Foundation
import SwiftUI
import Testing
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio

private func makeMessage(
    fromX: Double = 100, toX: Double = 200, posY: Double = 50,
    isAsync: Bool = false
) -> SequenceMessage {
    SequenceMessage(
        id: 0, label: "call()",
        fromX: fromX, toX: toX, posY: posY,
        isAsync: isAsync, isUnresolved: false, noteText: nil
    )
}

@Suite("NativeSequenceGeometry.isSelfLoop")
struct IsSelfLoopTests {

    @Test("same fromX and toX is a self-loop")
    func sameCoordinates() {
        #expect(NativeSequenceGeometry.isSelfLoop(message: makeMessage(fromX: 100, toX: 100)))
    }

    @Test("sub-pixel difference is still a self-loop")
    func subPixelDifference() {
        #expect(NativeSequenceGeometry.isSelfLoop(message: makeMessage(fromX: 100, toX: 100.5)))
    }

    @Test("different participants are not a self-loop")
    func differentCoordinates() {
        #expect(NativeSequenceGeometry.isSelfLoop(message: makeMessage(fromX: 100, toX: 200)) == false)
    }
}

@Suite("NativeSequenceGeometry.arrowStrokeStyle")
struct ArrowStrokeStyleTests {

    @Test("async messages are dashed")
    func asyncDashed() {
        let style = NativeSequenceGeometry.arrowStrokeStyle(isAsync: true)
        #expect(style.dash == [4, 3])
    }

    @Test("sync messages are solid")
    func syncSolid() {
        let style = NativeSequenceGeometry.arrowStrokeStyle(isAsync: false)
        #expect(style.dash.isEmpty)
    }
}

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

@Suite("NativeSequenceGeometry note sizing")
struct NoteGeometryTests {

    @Test("short notes use the minimum width")
    func minimumWidth() {
        #expect(NativeSequenceGeometry.noteWidth(for: "hi") == 100)
    }

    @Test("long notes scale with character count")
    func scalesWithCharacters() {
        let text = String(repeating: "x", count: 30)
        #expect(NativeSequenceGeometry.noteWidth(for: text) == 210)
    }

    @Test("note rect is centered on the given point")
    func noteCentered() {
        let rect = NativeSequenceGeometry.noteRect(text: "hi", centerX: 100, posY: 50)
        #expect(rect.midX == 100)
        #expect(rect.midY == 50)
    }
}
