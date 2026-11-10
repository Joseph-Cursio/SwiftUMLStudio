@testable import SwiftUMLBridgeFramework
import Testing

@Suite("SequenceSVGRenderer - participant sourceLocation")
struct SequenceSVGParticipantLocationTests {

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
            "Worker": FrameworkLocation(filePath: "/Worker.swift", line: 11, column: 8),
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
