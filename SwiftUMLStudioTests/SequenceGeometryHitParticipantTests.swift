import CoreGraphics
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio
import Testing

@Suite("NativeSequenceGeometry.hitParticipant")
struct SequenceGeometryHitParticipantTests {

    private func makeParticipant(
        name: String,
        centerX: Double,
        topY: Double = 20,
        bottomTopY: Double = 400,
        width: Double = 120,
        height: Double = 36
    ) -> SequenceParticipant {
        SequenceParticipant(
            name: name, centerX: centerX, topY: topY,
            width: width, height: height, bottomTopY: bottomTopY
        )
    }

    private func makeLayout(participants: [SequenceParticipant]) -> SequenceLayout {
        SequenceLayout(
            participants: participants, messages: [],
            title: "test", totalWidth: 800, totalHeight: 500,
            lifelineStartY: 56, lifelineEndY: 400
        )
    }

    @Test("a tap inside a top-row participant box returns that participant")
    func hitsTopBox() throws {
        let layout = makeLayout(participants: [
            makeParticipant(name: "Service", centerX: 100),
            makeParticipant(name: "Worker", centerX: 280),
        ])
        let hit = try #require(
            NativeSequenceGeometry.hitParticipant(in: layout, at: CGPoint(x: 100, y: 35))
        )
        #expect(hit.name == "Service")
    }

    @Test("a tap inside the bottom mirror box also matches")
    func hitsBottomBox() throws {
        let layout = makeLayout(participants: [
            makeParticipant(name: "Worker", centerX: 280, bottomTopY: 410)
        ])
        let hit = try #require(
            NativeSequenceGeometry.hitParticipant(in: layout, at: CGPoint(x: 280, y: 425))
        )
        #expect(hit.name == "Worker")
    }

    @Test("a tap on the lifeline (between the two boxes) is a miss")
    func missesLifeline() {
        let layout = makeLayout(participants: [
            makeParticipant(name: "Service", centerX: 100, bottomTopY: 400)
        ])
        // y=200 is well into the lifeline gap, between top (20-56) and bottom (400-436)
        #expect(
            NativeSequenceGeometry.hitParticipant(in: layout, at: CGPoint(x: 100, y: 200)) == nil
        )
    }

    @Test("a tap in empty space returns nil")
    func missesEmptySpace() {
        let layout = makeLayout(participants: [
            makeParticipant(name: "Service", centerX: 100)
        ])
        #expect(
            NativeSequenceGeometry.hitParticipant(in: layout, at: CGPoint(x: 700, y: 700)) == nil
        )
    }
}
