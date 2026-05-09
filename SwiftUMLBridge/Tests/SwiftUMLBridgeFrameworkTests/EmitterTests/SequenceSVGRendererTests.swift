import Testing
@testable import SwiftUMLBridgeFramework

@Suite("SequenceSVGRenderer - computeLayout")
struct SequenceSVGRendererTests {

    // MARK: - Helpers

    private func makeEdge(
        callerType: String = "Controller",
        callerMethod: String = "handle",
        calleeType: String? = "Service",
        calleeMethod: String = "process",
        isAsync: Bool = false,
        isUnresolved: Bool = false
    ) -> CallEdge {
        CallEdge(
            callerType: callerType,
            callerMethod: callerMethod,
            calleeType: calleeType,
            calleeMethod: calleeMethod,
            isAsync: isAsync,
            isUnresolved: isUnresolved
        )
    }

    // MARK: - computeLayout: Participants

    @Test("entry type is always the first participant")
    func entryTypeIsFirst() {
        let edges = [makeEdge()]
        let layout = SequenceSVGRenderer.computeLayout(
            traversedEdges: edges, entryType: "Controller", entryMethod: "handle"
        )
        #expect(layout.participants.first?.name == "Controller")
    }

    @Test("collects participants from resolved edges in appearance order")
    func participantOrder() {
        let edges = [
            makeEdge(calleeType: "ServiceA", calleeMethod: "run"),
            makeEdge(calleeType: "ServiceB", calleeMethod: "run"),
            makeEdge(calleeType: "ServiceA", calleeMethod: "again")
        ]
        let layout = SequenceSVGRenderer.computeLayout(
            traversedEdges: edges, entryType: "Controller", entryMethod: "handle"
        )
        let names = layout.participants.map(\.name)
        #expect(names == ["Controller", "ServiceA", "ServiceB"])
    }

    @Test("unresolved edges do not add participants")
    func unresolvedEdgesExcluded() {
        let edges = [
            makeEdge(calleeType: nil, calleeMethod: "unknown", isUnresolved: true)
        ]
        let layout = SequenceSVGRenderer.computeLayout(
            traversedEdges: edges, entryType: "Controller", entryMethod: "handle"
        )
        #expect(layout.participants.count == 1)
        #expect(layout.participants[0].name == "Controller")
    }

    @Test("empty edges produces single participant for entry type")
    func emptyEdges() {
        let layout = SequenceSVGRenderer.computeLayout(
            traversedEdges: [], entryType: "App", entryMethod: "main"
        )
        #expect(layout.participants.count == 1)
        #expect(layout.participants[0].name == "App")
    }

    // MARK: - computeLayout: Messages

    @Test("creates message for each resolved edge")
    func messageCount() {
        let edges = [
            makeEdge(calleeMethod: "aaa"),
            makeEdge(calleeMethod: "bbb")
        ]
        let layout = SequenceSVGRenderer.computeLayout(
            traversedEdges: edges, entryType: "Controller", entryMethod: "handle"
        )
        #expect(layout.messages.count == 2)
    }

    @Test("message labels include method name with parentheses")
    func messageLabels() {
        let edges = [makeEdge(calleeMethod: "doWork")]
        let layout = SequenceSVGRenderer.computeLayout(
            traversedEdges: edges, entryType: "Controller", entryMethod: "handle"
        )
        #expect(layout.messages[0].label == "doWork()")
    }

    @Test("async edge produces async message")
    func asyncMessage() {
        let edges = [makeEdge(isAsync: true)]
        let layout = SequenceSVGRenderer.computeLayout(
            traversedEdges: edges, entryType: "Controller", entryMethod: "handle"
        )
        #expect(layout.messages[0].isAsync == true)
    }

    @Test("unresolved edge produces unresolved message with note text")
    func unresolvedMessage() {
        let edges = [
            makeEdge(calleeType: nil, calleeMethod: "mystery", isUnresolved: true)
        ]
        let layout = SequenceSVGRenderer.computeLayout(
            traversedEdges: edges, entryType: "Controller", entryMethod: "handle"
        )
        #expect(layout.messages.count == 1)
        #expect(layout.messages[0].isUnresolved == true)
        #expect(layout.messages[0].noteText == "Unresolved: mystery()")
    }

    // MARK: - computeLayout: Dimensions

    @Test("total width scales with participant count")
    func totalWidthScales() {
        let singleLayout = SequenceSVGRenderer.computeLayout(
            traversedEdges: [], entryType: "App", entryMethod: "run"
        )
        let edges = [
            makeEdge(calleeType: "ServiceA", calleeMethod: "run"),
            makeEdge(calleeType: "ServiceB", calleeMethod: "run")
        ]
        let multiLayout = SequenceSVGRenderer.computeLayout(
            traversedEdges: edges, entryType: "App", entryMethod: "run"
        )
        #expect(multiLayout.totalWidth > singleLayout.totalWidth)
    }

    @Test("total height scales with message count")
    func totalHeightScales() {
        let fewEdges = [makeEdge()]
        let manyEdges = [
            makeEdge(calleeMethod: "aaa"),
            makeEdge(calleeMethod: "bbb"),
            makeEdge(calleeMethod: "ccc"),
            makeEdge(calleeMethod: "ddd"),
            makeEdge(calleeMethod: "eee")
        ]
        let fewLayout = SequenceSVGRenderer.computeLayout(
            traversedEdges: fewEdges, entryType: "Ctrl", entryMethod: "run"
        )
        let manyLayout = SequenceSVGRenderer.computeLayout(
            traversedEdges: manyEdges, entryType: "Ctrl", entryMethod: "run"
        )
        #expect(manyLayout.totalHeight > fewLayout.totalHeight)
    }

    @Test("layout title combines entry type and method")
    func layoutTitle() {
        let layout = SequenceSVGRenderer.computeLayout(
            traversedEdges: [], entryType: "MyApp", entryMethod: "start"
        )
        #expect(layout.title == "MyApp.start")
    }

    // MARK: - computeLayout: Self-Calls

    @Test("self-call has same fromX and toX")
    func selfCallPositioning() {
        let edges = [
            makeEdge(
                callerType: "Service",
                calleeType: "Service",
                calleeMethod: "retry"
            )
        ]
        let layout = SequenceSVGRenderer.computeLayout(
            traversedEdges: edges, entryType: "Service", entryMethod: "run"
        )
        let msg = layout.messages[0]
        #expect(msg.fromX == msg.toX)
    }
}

@Suite("SequenceSVGRenderer - participant sourceLocation")
struct SequenceSVGRendererParticipantLocationTests {

    private typealias FrameworkLocation = SwiftUMLBridgeFramework.SourceLocation

    private func edge(callerType: String, calleeType: String) -> CallEdge {
        CallEdge(
            callerType: callerType, callerMethod: "run",
            calleeType: calleeType, calleeMethod: "doWork",
            isAsync: false, isUnresolved: false
        )
    }

    @Test("participants without a typeLocations entry have nil sourceLocation")
    func emptyMapMeansNilLocations() {
        let layout = SequenceSVGRenderer.computeLayout(
            traversedEdges: [edge(callerType: "Service", calleeType: "Worker")],
            entryType: "Service", entryMethod: "run"
        )
        for participant in layout.participants {
            #expect(participant.sourceLocation == nil)
        }
    }

    @Test("typeLocations entries are stamped onto matching participants")
    func mapStampsLocations() throws {
        let map: [String: FrameworkLocation] = [
            "Service": FrameworkLocation(filePath: "/Service.swift", line: 4, column: 7),
            "Worker": FrameworkLocation(filePath: "/Worker.swift", line: 11, column: 8)
        ]
        let layout = SequenceSVGRenderer.computeLayout(
            traversedEdges: [edge(callerType: "Service", calleeType: "Worker")],
            entryType: "Service", entryMethod: "run",
            typeLocations: map
        )
        let service = try #require(layout.participants.first { $0.name == "Service" })
        let worker = try #require(layout.participants.first { $0.name == "Worker" })
        #expect(service.sourceLocation == map["Service"])
        #expect(worker.sourceLocation == map["Worker"])
    }

    @Test("participants without a matching map entry stay nil")
    func unmappedStaysNil() throws {
        let map: [String: FrameworkLocation] = [
            "Service": FrameworkLocation(filePath: "/Service.swift", line: 4, column: 7)
        ]
        let layout = SequenceSVGRenderer.computeLayout(
            traversedEdges: [edge(callerType: "Service", calleeType: "Worker")],
            entryType: "Service", entryMethod: "run",
            typeLocations: map
        )
        let worker = try #require(layout.participants.first { $0.name == "Worker" })
        #expect(worker.sourceLocation == nil)
    }
}
