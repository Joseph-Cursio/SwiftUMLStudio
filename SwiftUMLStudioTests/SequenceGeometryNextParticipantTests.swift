import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio
import Testing

@Suite("NativeSequenceGeometry.nextParticipant (arrow navigation)")
struct SequenceGeometryNextParticipantTests {

    private func makeParticipant(name: String, centerX: Double) -> SequenceParticipant {
        SequenceParticipant(name: name, centerX: centerX)
    }

    private func makeLayout(participants: [SequenceParticipant]) -> SequenceLayout {
        SequenceLayout(
            participants: participants, messages: [],
            title: "test", totalWidth: 800, totalHeight: 500,
            lifelineStartY: 56, lifelineEndY: 400
        )
    }

    @Test("right from the leftmost participant selects the immediate neighbor")
    func rightFromLeftmost() throws {
        let layout = makeLayout(participants: [
            makeParticipant(name: "A", centerX: 100),
            makeParticipant(name: "B", centerX: 250),
            makeParticipant(name: "C", centerX: 400),
        ])
        let next = try #require(
            NativeSequenceGeometry.nextParticipant(in: layout, from: "A", direction: .right)
        )
        #expect(next.name == "B")
    }

    @Test("left from a middle participant returns the previous one")
    func leftFromMiddle() throws {
        let layout = makeLayout(participants: [
            makeParticipant(name: "A", centerX: 100),
            makeParticipant(name: "B", centerX: 250),
            makeParticipant(name: "C", centerX: 400),
        ])
        let next = try #require(
            NativeSequenceGeometry.nextParticipant(in: layout, from: "B", direction: .left)
        )
        #expect(next.name == "A")
    }

    @Test("right from the rightmost participant returns nil")
    func rightFromRightmost() {
        let layout = makeLayout(participants: [
            makeParticipant(name: "A", centerX: 100),
            makeParticipant(name: "B", centerX: 250),
        ])
        #expect(
            NativeSequenceGeometry.nextParticipant(in: layout, from: "B", direction: .right) == nil
        )
    }

    @Test("up and down are no-ops on a single-row layout")
    func upDownAreNoops() {
        let layout = makeLayout(participants: [
            makeParticipant(name: "A", centerX: 100),
            makeParticipant(name: "B", centerX: 250),
        ])
        #expect(NativeSequenceGeometry.nextParticipant(in: layout, from: "A", direction: .upward) == nil)
        #expect(NativeSequenceGeometry.nextParticipant(in: layout, from: "A", direction: .down) == nil)
    }

    @Test("firstParticipant returns the leftmost")
    func firstParticipantPicksLeftmost() throws {
        let layout = makeLayout(participants: [
            makeParticipant(name: "right", centerX: 400),
            makeParticipant(name: "left", centerX: 100),
            makeParticipant(name: "mid", centerX: 250),
        ])
        let first = try #require(NativeSequenceGeometry.firstParticipant(in: layout))
        #expect(first.name == "left")
    }
}
