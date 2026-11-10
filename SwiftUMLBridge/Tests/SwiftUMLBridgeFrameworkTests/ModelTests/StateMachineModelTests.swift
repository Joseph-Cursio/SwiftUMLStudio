@testable import SwiftUMLBridgeFramework
import Testing

@Suite("DetectionConfidence")
struct DetectionConfidenceTests {

    @Test("low < medium < high")
    func ordering() {
        #expect(DetectionConfidence.low < DetectionConfidence.medium)
        #expect(DetectionConfidence.medium < DetectionConfidence.high)
        #expect(DetectionConfidence.low < DetectionConfidence.high)
    }

    @Test("rank values are stable")
    func rankValues() {
        #expect(DetectionConfidence.low.rank == 0)
        #expect(DetectionConfidence.medium.rank == 1)
        #expect(DetectionConfidence.high.rank == 2)
    }

    @Test("sorting high-first uses the > operator")
    func sortHighestFirst() {
        let unsorted: [DetectionConfidence] = [.low, .high, .medium]
        let sorted = unsorted.sorted { $0 > $1 }
        #expect(sorted == [.high, .medium, .low])
    }

    @Test("min across mixed confidences returns the weakest")
    func minAcrossArray() {
        let mixed: [DetectionConfidence] = [.high, .medium, .low, .high]
        #expect(mixed.min() == .low)
    }
}

@Suite("StateMachineModel")
struct StateMachineModelTests {

    @Test("identifier combines host and enum type")
    func identifierFormat() {
        let model = StateMachineModel(
            hostType: "Router", enumType: "Route",
            states: [], transitions: []
        )
        #expect(model.identifier == "Router.Route")
    }

    @Test("defaults to high confidence with no notes")
    func defaultConfidence() {
        let model = StateMachineModel(
            hostType: "H", enumType: "E",
            states: [], transitions: []
        )
        #expect(model.confidence == .high)
        #expect(model.notes.isEmpty)
    }
}
