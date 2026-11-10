import CoreGraphics
import Foundation
import SwiftUI
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio
import Testing

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
