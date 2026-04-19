import Foundation

/// A rendered state machine diagram.
///
/// M1 emits PlantUML only. Mermaid/Nomnoml/SVG will follow in M2 (Mermaid fallback
/// for Nomnoml, SVG via the Mermaid HTML pipeline).
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
        self.format = configuration.format
        switch configuration.format {
        case .plantuml:
            self.text = StateScript.buildPlantUMLText(model: model)
        case .mermaid, .nomnoml, .svg:
            // M1: non-PlantUML formats fall back to PlantUML text for now.
            // M2 will add a native Mermaid `stateDiagram-v2` emitter and reuse
            // the Mermaid HTML pipeline for SVG.
            self.text = StateScript.buildPlantUMLText(model: model)
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

        if let initial = model.states.first(where: { $0.isInitial }) {
            lines.append("[*] --> \(initial.name)")
        }

        for transition in model.transitions {
            var line = "\(transition.from) --> \(transition.toState)"
            if let trigger = transition.trigger, !trigger.isEmpty {
                line += " : \(trigger)()"
            }
            lines.append(line)
        }

        for state in model.states where state.isFinal {
            lines.append("\(state.name) --> [*]")
        }

        lines.append("@enduml")
        return lines.joined(separator: "\n")
    }
}

extension StateScript: DiagramOutputting {}
