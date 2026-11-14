import Foundation
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio
import Testing

// MARK: - InsightEngine Tests

@MainActor
struct InsightEngineTests {

    @Test("generates cycle warning when cycles present")
    func cycleWarning() throws {
        let summary = makeSummary(cycleWarnings: ["TypeA", "TypeB"])
        let insights = InsightEngine.generate(from: summary)
        let cycleInsight = insights.first { $0.title.contains("Circular") }
        #expect(cycleInsight != nil, "Expected a cycle warning insight")
        #expect(cycleInsight?.severity == .warning)
    }

    @Test("generates composition insight when types exist")
    func compositionInsight() {
        let summary = makeSummary(totalTypes: 7, typeBreakdown: ["Classes": 4, "Structs": 3])
        let insights = InsightEngine.generate(from: summary)
        let comp = insights.first { $0.title.contains("composition") }
        #expect(comp != nil, "Expected a composition insight")
    }

    @Test("generates high-connectivity insight for popular types")
    func highConnectivity() {
        let summary = makeSummary(
            topConnectedTypes: [(name: "Database", connectionCount: 12)]
        )
        let insights = InsightEngine.generate(from: summary)
        let conn = insights.first { $0.title.contains("Database") }
        #expect(conn != nil, "Expected a connectivity insight for Database")
        #expect(conn?.severity == .noteworthy)
    }

    @Test("generates entry points insight when methods available")
    func entryPointInsight() {
        let summary = makeSummary(entryPoints: ["Foo.bar", "Baz.qux"])
        let insights = InsightEngine.generate(from: summary)
        let method = insights.first { $0.title.contains("methods") }
        #expect(method != nil, "Expected an entry points insight")
    }

    @Test("generates state machine insight when candidates detected")
    func stateMachineInsight() {
        let model = StateMachineModel(
            hostType: "TrafficLight", enumType: "Light",
            states: [StateMachineState(name: "red", isInitial: true)],
            transitions: []
        )
        let summary = makeSummary(stateMachines: [model])
        let insights = InsightEngine.generate(from: summary)
        let stateInsight = insights.first { $0.title.contains("state machine") }
        #expect(stateInsight != nil, "Expected a state machine insight")
        #expect(stateInsight?.description.contains("TrafficLight") == true)
    }
}
