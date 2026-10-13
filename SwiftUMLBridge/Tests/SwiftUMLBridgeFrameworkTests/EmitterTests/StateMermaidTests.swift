import Testing
@testable import SwiftUMLBridgeFramework

@Suite("StateScript — Mermaid")
struct StateMermaidTests {

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

    private func makeScript(model: StateMachineModel, format: DiagramFormat = .mermaid) -> StateScript {
        var config = Configuration.default
        config.format = format
        return StateScript(model: model, configuration: config)
    }

    @Test("starts with stateDiagram-v2 header")
    func startsWithHeader() {
        let script = makeScript(model: makeModel())
        #expect(script.text.hasPrefix("stateDiagram-v2"))
    }

    @Test("includes comment with host.enum label")
    func includesLabelComment() {
        let script = makeScript(model: makeModel())
        #expect(script.text.contains("%% title: TrafficLight.Light"))
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

    @Test("does not include PlantUML delimiters")
    func noPlantUMLDelimiters() {
        let script = makeScript(model: makeModel())
        #expect(script.text.contains("@startuml") == false)
        #expect(script.text.contains("@enduml") == false)
    }

    @Test("guarded transition renders trigger and [guard] in label")
    func emitsGuardedTransition() {
        let model = StateMachineModel(
            hostType: "Runner",
            enumType: "Flow",
            states: [
                StateMachineState(name: "idle", isInitial: true),
                StateMachineState(name: "retrying")
            ],
            transitions: [
                StateTransition(
                    from: "idle", toState: "retrying",
                    trigger: "tick", guardText: "retryCount > 0"
                )
            ]
        )
        let script = makeScript(model: model)
        #expect(script.text.contains("idle --> retrying : tick() [retryCount > 0]"))
    }

    @Test("nomnoml format falls back to Mermaid text, reports mermaid")
    func nomnomlFallsBackToMermaidText() {
        let script = makeScript(model: makeModel(), format: .nomnoml)
        #expect(script.format == .mermaid)
        #expect(script.text.hasPrefix("stateDiagram-v2"))
    }

    @Test("svg format reports mermaid so web view renders via Mermaid pipeline")
    func svgReportsMermaidFormat() {
        let script = makeScript(model: makeModel(), format: .svg)
        #expect(script.format == .mermaid)
        #expect(script.text.hasPrefix("stateDiagram-v2"))
    }
}
