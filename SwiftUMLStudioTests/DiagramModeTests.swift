//  Tests for DiagramMode, FileNode, and MermaidHTMLBuilder.

@testable import SwiftUMLStudio
import Testing

// MARK: - DiagramMode Tests

@Suite("DiagramMode") @MainActor
struct DiagramModeTests {

    /// Asserted as an exact list rather than a bare count so that adding a case
    /// fails with a message naming the newcomer, instead of an opaque `7 == 6`.
    @Test("allCases is exactly the known modes, in declaration order")
    func allCasesIsExactList() {
        #expect(DiagramMode.allCases == [
            .classDiagram,
            .sequenceDiagram,
            .dependencyGraph,
            .stateMachine,
            .activityDiagram,
            .erDiagram,
            .componentDiagram,
        ])
    }

    @Test("classDiagram raw value is 'Class Diagram'")
    func classDiagramRawValue() {
        #expect(DiagramMode.classDiagram.rawValue == "Class Diagram")
    }

    @Test("sequenceDiagram raw value is 'Sequence Diagram'")
    func sequenceDiagramRawValue() {
        #expect(DiagramMode.sequenceDiagram.rawValue == "Sequence Diagram")
    }

    @Test("dependencyGraph raw value is 'Dependency Graph'")
    func dependencyGraphRawValue() {
        #expect(DiagramMode.dependencyGraph.rawValue == "Dependency Graph")
    }

    @Test("stateMachine raw value is 'State Machine'")
    func stateMachineRawValue() {
        #expect(DiagramMode.stateMachine.rawValue == "State Machine")
    }

    @Test("activityDiagram raw value is 'Activity Diagram'")
    func activityDiagramRawValue() {
        #expect(DiagramMode.activityDiagram.rawValue == "Activity Diagram")
    }

    @Test("erDiagram raw value is 'ER Diagram'")
    func erDiagramRawValue() {
        #expect(DiagramMode.erDiagram.rawValue == "ER Diagram")
    }

    @Test("componentDiagram raw value is 'Component Diagram'")
    func componentDiagramRawValue() {
        #expect(DiagramMode.componentDiagram.rawValue == "Component Diagram")
    }

    @Test("id equals rawValue for all cases")
    func idEqualsRawValue() {
        for mode in DiagramMode.allCases {
            #expect(mode.id == mode.rawValue)
        }
    }

    @Test("allCases contains every case")
    func allCasesContainsEverything() {
        let cases = DiagramMode.allCases
        #expect(cases.contains(.classDiagram))
        #expect(cases.contains(.sequenceDiagram))
        #expect(cases.contains(.dependencyGraph))
        #expect(cases.contains(.stateMachine))
        #expect(cases.contains(.activityDiagram))
        #expect(cases.contains(.erDiagram))
        #expect(cases.contains(.componentDiagram))
    }

    @Test("can be initialized from raw value")
    func initFromRawValue() {
        #expect(DiagramMode(rawValue: "Class Diagram") == .classDiagram)
        #expect(DiagramMode(rawValue: "Sequence Diagram") == .sequenceDiagram)
        #expect(DiagramMode(rawValue: "Dependency Graph") == .dependencyGraph)
        #expect(DiagramMode(rawValue: "State Machine") == .stateMachine)
        #expect(DiagramMode(rawValue: "Activity Diagram") == .activityDiagram)
        #expect(DiagramMode(rawValue: "ER Diagram") == .erDiagram)
        #expect(DiagramMode(rawValue: "Component Diagram") == .componentDiagram)
        #expect(DiagramMode(rawValue: "nonexistent") == nil)
    }
}
