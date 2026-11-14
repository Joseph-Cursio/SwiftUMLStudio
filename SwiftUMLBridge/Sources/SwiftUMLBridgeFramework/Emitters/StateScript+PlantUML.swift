// MARK: - PlantUML

extension StateScript {
    static func buildPlantUMLText(model: StateMachineModel) -> String {
        var lines = ["@startuml", "title \(model.hostType).\(model.enumType)"]
        lines += transitionLines(model: model)
        lines.append("@enduml")
        return lines.joined(separator: "\n")
    }

    /// The shared body of a state diagram — the initial pseudo-state edge, every
    /// transition, and the final-state edges. PlantUML and Mermaid wrap this in
    /// their own header/footer; the body lines are identical.
    static func transitionLines(model: StateMachineModel) -> [String] {
        var lines: [String] = []

        let hasWildcardSource = model.transitions.contains { $0.from == "*" }
        if !hasWildcardSource, let initial = model.states.first(where: \.isInitial) {
            lines.append("[*] --> \(initial.name)")
        }

        for transition in model.transitions {
            let from = renderStateToken(transition.from)
            let toState = renderStateToken(transition.toState)
            lines.append("\(from) --> \(toState)\(transitionLabel(transition))")
        }

        for state in model.states where state.isFinal {
            lines.append("\(state.name) --> [*]")
        }

        return lines
    }

    static func transitionLabel(_ transition: StateTransition) -> String {
        var parts: [String] = []
        if let trigger = transition.trigger, !trigger.isEmpty {
            parts.append("\(trigger)()")
        }
        if let guardText = transition.guardText, !guardText.isEmpty {
            parts.append("[\(guardText)]")
        }
        return parts.isEmpty ? "" : " : " + parts.joined(separator: " ")
    }
}
