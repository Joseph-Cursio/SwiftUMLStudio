import Testing
@testable import SwiftUMLBridgeFramework

@Suite("StateScript — PlantUML")
struct StatePlantUMLTests {

    private func makeModel() -> StateMachineModel {
        StateMachineModel(
            hostType: "TrafficLight",
            enumType: "Light",
            states: [
                StateMachineState(name: "red", isInitial: true),
                StateMachineState(name: "yellow"),
                StateMachineState(name: "green")
            ],
            transitions: [
                StateTransition(from: "red", toState: "green", trigger: "advance"),
                StateTransition(from: "green", toState: "yellow", trigger: "advance"),
                StateTransition(from: "yellow", toState: "red", trigger: "advance")
            ]
        )
    }

    private func makeScript(model: StateMachineModel, format: DiagramFormat = .plantuml) -> StateScript {
        var config = Configuration.default
        config.format = format
        return StateScript(model: model, configuration: config)
    }

    @Test("starts with @startuml")
    func startsWithStartuml() {
        let script = makeScript(model: makeModel())
        #expect(script.text.hasPrefix("@startuml"))
    }

    @Test("ends with @enduml")
    func endsWithEnduml() {
        let script = makeScript(model: makeModel())
        let lastLine = script.text.components(separatedBy: "\n").last(where: { !$0.isEmpty })
        #expect(lastLine == "@enduml")
    }

    @Test("contains title line")
    func containsTitleLine() {
        let script = makeScript(model: makeModel())
        #expect(script.text.contains("title TrafficLight.Light"))
    }

    @Test("emits [*] --> initial state")
    func emitsInitialArrow() {
        let script = makeScript(model: makeModel())
        #expect(script.text.contains("[*] --> red"))
    }

    @Test("emits each transition with trigger")
    func emitsTransitionsWithTriggers() {
        let script = makeScript(model: makeModel())
        #expect(script.text.contains("red --> green : advance()"))
        #expect(script.text.contains("green --> yellow : advance()"))
        #expect(script.text.contains("yellow --> red : advance()"))
    }

    @Test("final state gets arrow to [*]")
    func emitsFinalArrow() {
        let model = StateMachineModel(
            hostType: "Runner",
            enumType: "Flow",
            states: [
                StateMachineState(name: "idle", isInitial: true),
                StateMachineState(name: "running"),
                StateMachineState(name: "done", isFinal: true)
            ],
            transitions: [
                StateTransition(from: "idle", toState: "running", trigger: "run"),
                StateTransition(from: "running", toState: "done", trigger: "run")
            ]
        )
        let script = makeScript(model: model)
        #expect(script.text.contains("done --> [*]"))
    }

    @Test("transition without trigger omits arrow label")
    func transitionWithoutTriggerHasNoLabel() {
        let model = StateMachineModel(
            hostType: "Host",
            enumType: "Flow",
            states: [StateMachineState(name: "a", isInitial: true), StateMachineState(name: "b")],
            transitions: [StateTransition(from: "a", toState: "b")]
        )
        let script = makeScript(model: model)
        #expect(script.text.contains("a --> b"))
        #expect(script.text.contains("a --> b : ") == false)
    }

    @Test("empty script value is safe to use")
    func emptyScript() {
        let script = StateScript.empty
        #expect(script.text.isEmpty)
        #expect(script.format == .plantuml)
    }

    @Test("M1 non-PlantUML formats fall back to PlantUML text")
    func mermaidFallsBackToPlantUML() {
        let mermaidScript = makeScript(model: makeModel(), format: .mermaid)
        #expect(mermaidScript.text.contains("@startuml"))
        #expect(mermaidScript.format == .mermaid)
    }

    @Test("StateScript conforms to DiagramOutputting")
    func conformsToDiagramOutputting() {
        let script: any DiagramOutputting = makeScript(model: makeModel())
        #expect(script.text.hasPrefix("@startuml"))
    }
}
