import Foundation
import Testing
@testable import SwiftUMLStudio

@Suite("HistoryItemRow.displayMode")
@MainActor
struct HistoryItemRowDisplayModeTests {

    @Test("nil mode falls back to \"Diagram\"")
    func nilModeFallsBack() {
        #expect(HistoryItemRow.displayMode(mode: nil, entryPoint: nil) == "Diagram")
        #expect(HistoryItemRow.displayMode(mode: nil, entryPoint: "ignored") == "Diagram")
    }

    @Test("class diagram returns mode raw value without annotation")
    func classDiagramPlain() {
        #expect(
            HistoryItemRow.displayMode(
                mode: DiagramMode.classDiagram.rawValue, entryPoint: nil
            ) == "Class Diagram"
        )
    }

    @Test("dependency graph always includes entry point when present")
    func dependencyGraphShowsDetail() {
        #expect(
            HistoryItemRow.displayMode(
                mode: DiagramMode.dependencyGraph.rawValue, entryPoint: "types"
            ) == "Dependency Graph (types)"
        )
    }

    @Test("dependency graph with nil entry point omits parentheses")
    func dependencyGraphNilEntryPlain() {
        #expect(
            HistoryItemRow.displayMode(
                mode: DiagramMode.dependencyGraph.rawValue, entryPoint: nil
            ) == "Dependency Graph"
        )
    }

    @Test("sequence diagram shows entry point only when non-empty")
    func sequenceDiagramShowsEntry() {
        #expect(
            HistoryItemRow.displayMode(
                mode: DiagramMode.sequenceDiagram.rawValue, entryPoint: "Foo.bar"
            ) == "Sequence Diagram (Foo.bar)"
        )
        #expect(
            HistoryItemRow.displayMode(
                mode: DiagramMode.sequenceDiagram.rawValue, entryPoint: ""
            ) == "Sequence Diagram"
        )
    }

    @Test("state machine shows identifier only when non-empty")
    func stateMachineShowsIdentifier() {
        #expect(
            HistoryItemRow.displayMode(
                mode: DiagramMode.stateMachine.rawValue, entryPoint: "TrafficLight.Light"
            ) == "State Machine (TrafficLight.Light)"
        )
        #expect(
            HistoryItemRow.displayMode(
                mode: DiagramMode.stateMachine.rawValue, entryPoint: ""
            ) == "State Machine"
        )
    }
}
