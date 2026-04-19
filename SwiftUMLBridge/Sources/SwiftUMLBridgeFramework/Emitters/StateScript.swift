import Foundation

/// A rendered state machine diagram.
public struct StateScript: Sendable {
    /// The diagram text.
    public let text: String

    /// The output format.
    public let format: DiagramFormat

    /// An empty script (used when no candidate matches).
    public static let empty = StateScript(text: "", format: .plantuml)

    /// Encode diagram text for PlantUML URL embedding.
    public func encodeText() -> String {
        DiagramText(rawValue: text).encodedValue
    }

    internal init(model: StateMachineModel, configuration: Configuration) {
        switch configuration.format {
        case .plantuml:
            self.text = StateScript.buildPlantUMLText(model: model)
            self.format = .plantuml
        case .mermaid:
            self.text = StateScript.buildMermaidText(model: model)
            self.format = .mermaid
        case .nomnoml:
            // nomnoml has no state-diagram syntax; fall back to Mermaid text
            // (matches SequenceScript's behavior for the same limitation).
            self.text = StateScript.buildMermaidText(model: model)
            self.format = .nomnoml
        case .svg:
            // No native SVG layout engine for state diagrams yet; piggyback on
            // the Mermaid pipeline by emitting Mermaid text and overriding the
            // reported format so DiagramWebView renders it through
            // MermaidHTMLBuilder.
            self.text = StateScript.buildMermaidText(model: model)
            self.format = .mermaid
        }
    }

    private init(text: String, format: DiagramFormat) {
        self.text = text
        self.format = format
    }
}

// MARK: - PlantUML

private extension StateScript {
    static func buildPlantUMLText(model: StateMachineModel) -> String {
        var lines: [String] = [
            "@startuml",
            "title \(model.hostType).\(model.enumType)"
        ]

        let hasWildcardSource = model.transitions.contains { $0.from == "*" }
        if !hasWildcardSource, let initial = model.states.first(where: { $0.isInitial }) {
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

        lines.append("@enduml")
        return lines.joined(separator: "\n")
    }

    /// Normalize the wildcard source token `*` to PlantUML / Mermaid's initial
    /// pseudo-state `[*]`.
    static func renderStateToken(_ name: String) -> String {
        name == "*" ? "[*]" : name
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

// MARK: - Mermaid

private extension StateScript {
    static func buildMermaidText(model: StateMachineModel) -> String {
        var lines: [String] = [
            "stateDiagram-v2",
            "%% title: \(model.hostType).\(model.enumType)"
        ]

        let hasWildcardSource = model.transitions.contains { $0.from == "*" }
        if !hasWildcardSource, let initial = model.states.first(where: { $0.isInitial }) {
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

        return lines.joined(separator: "\n")
    }
}

extension StateScript: DiagramOutputting {}
