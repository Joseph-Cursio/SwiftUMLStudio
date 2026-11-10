import Testing
@testable import SwiftUMLBridgeFramework

@Suite("SequenceLayout Tests")
struct SequenceLayoutTests {

    // MARK: - SequenceLayout

    @Test("initializes with all defaults")
    func defaultInit() {
        let layout = SequenceLayout()
        #expect(layout.participants.isEmpty)
        #expect(layout.messages.isEmpty)
        #expect(layout.title.isEmpty)
        #expect(layout.totalWidth == 0)
        #expect(layout.totalHeight == 0)
        #expect(layout.lifelineStartY == 0)
        #expect(layout.lifelineEndY == 0)
    }

    @Test("initializes with provided values")
    func fullInit() {
        let participant = SequenceParticipant(name: "TypeA", centerX: 100)
        let message = SequenceMessage(
            id: 0, label: "doWork()", fromX: 100, toX: 280, posY: 80
        )
        let layout = SequenceLayout(
            participants: [participant],
            messages: [message],
            title: "TypeA.run",
            totalWidth: 400,
            totalHeight: 300,
            lifelineStartY: 56,
            lifelineEndY: 260
        )
        #expect(layout.participants.count == 1)
        #expect(layout.messages.count == 1)
        #expect(layout.title == "TypeA.run")
        #expect(layout.totalWidth == 400)
        #expect(layout.totalHeight == 300)
    }

    // MARK: - SequenceParticipant

    @Test("participant uses name as id")
    func participantIdentifiable() {
        let participant = SequenceParticipant(name: "MyService")
        #expect(participant.id == "MyService")
        #expect(participant.name == "MyService")
    }

    @Test("participant has sensible defaults")
    func participantDefaults() {
        let participant = SequenceParticipant(name: "Svc")
        #expect(participant.centerX == 0)
        #expect(participant.topY == 0)
        #expect(participant.width == 120)
        #expect(participant.height == 36)
        #expect(participant.bottomTopY == 0)
    }

    @Test("participant stores custom positioning")
    func participantCustomPosition() {
        let participant = SequenceParticipant(
            name: "Controller",
            centerX: 250,
            topY: 20,
            width: 140,
            height: 40,
            bottomTopY: 300
        )
        #expect(participant.centerX == 250)
        #expect(participant.topY == 20)
        #expect(participant.width == 140)
        #expect(participant.height == 40)
        #expect(participant.bottomTopY == 300)
    }

    // MARK: - SequenceMessage

    @Test("message initializes with defaults for optional fields")
    func messageDefaults() {
        let msg = SequenceMessage(
            id: 0, label: "fetch()", fromX: 100, toX: 280, posY: 80
        )
        #expect(msg.id == 0)
        #expect(msg.label == "fetch()")
        #expect(msg.fromX == 100)
        #expect(msg.toX == 280)
        #expect(msg.posY == 80)
        #expect(msg.isAsync == false)
        #expect(msg.isUnresolved == false)
        #expect(msg.noteText == nil)
    }

    @Test("message stores async flag")
    func messageAsync() {
        let msg = SequenceMessage(
            id: 1, label: "load()", fromX: 100, toX: 280, posY: 120, isAsync: true
        )
        #expect(msg.isAsync == true)
    }

    @Test("message stores unresolved flag and note text")
    func messageUnresolved() {
        let msg = SequenceMessage(
            id: 2, label: "unknown()", fromX: 100, toX: 160, posY: 160,
            isUnresolved: true, noteText: "Unresolved: unknown()"
        )
        #expect(msg.isUnresolved == true)
        #expect(msg.noteText == "Unresolved: unknown()")
    }

    @Test("message conforms to Identifiable with Int id")
    func messageIdentifiable() {
        let msgA = SequenceMessage(id: 0, label: "a()", fromX: 0, toX: 100, posY: 0)
        let msgB = SequenceMessage(id: 1, label: "b()", fromX: 0, toX: 100, posY: 0)
        #expect(msgA.id != msgB.id)
    }
}
