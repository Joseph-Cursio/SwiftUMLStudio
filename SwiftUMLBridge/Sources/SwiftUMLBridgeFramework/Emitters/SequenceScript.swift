import Foundation

/// A rendered sequence diagram in PlantUML or Mermaid format.
public struct SequenceScript: Sendable {
    /// The diagram text.
    public let text: String

    /// The output format.
    public let format: DiagramFormat

    /// Positioned sequence layout (available when format is `.svg`).
    public let sequenceLayout: SequenceLayout?

    /// An empty script (used when no entry point matches).
    public static let empty = SequenceScript(text: "", format: .plantuml)

    /// Encode diagram text for PlantUML URL embedding (same encoding as DiagramScript).
    public func encodeText() -> String {
        DiagramText(rawValue: text).encodedValue
    }

    internal init(
        traversedEdges: [CallEdge],
        entryType: String,
        entryMethod: String,
        configuration: Configuration,
        typeLocations: [String: SourceLocation] = [:]
    ) {
        self.format = configuration.format
        switch configuration.format {
        case .plantuml:
            self.text = SequenceScript.buildPlantUMLText(
                traversedEdges: traversedEdges, entryType: entryType, entryMethod: entryMethod
            )
            self.sequenceLayout = nil
        case .mermaid, .nomnoml:
            // nomnoml does not support sequence diagrams; fall back to Mermaid
            self.text = SequenceScript.buildMermaidText(
                traversedEdges: traversedEdges, entryType: entryType, entryMethod: entryMethod
            )
            self.sequenceLayout = nil
        case .svg:
            let layout = SequenceSVGRenderer.computeLayout(
                traversedEdges: traversedEdges,
                entryType: entryType,
                entryMethod: entryMethod,
                typeLocations: typeLocations
            )
            self.text = SequenceSVGRenderer.renderFromLayout(layout)
            self.sequenceLayout = layout
        }
    }

    private init(text: String, format: DiagramFormat) {
        self.text = text
        self.format = format
        self.sequenceLayout = nil
    }
}

// MARK: - PlantUML

private extension SequenceScript {
    static func buildPlantUMLText(
        traversedEdges: [CallEdge],
        entryType: String,
        entryMethod: String
    ) -> String {
        var lines: [String] = [
            "@startuml",
            "title \(entryType).\(entryMethod)"
        ]

        // Collect participants in order of first appearance
        var participants: [String] = [entryType]
        for edge in traversedEdges {
            if !edge.isUnresolved, let calleeType = edge.calleeType,
               !participants.contains(calleeType) {
                participants.append(calleeType)
            }
        }
        for participant in participants {
            lines.append("participant \(participant)")
        }

        lines.append("")

        // Emit call lines
        for edge in traversedEdges {
            if edge.isUnresolved {
                lines.append("note right: Unresolved: \(edge.calleeMethod)()")
            } else if let calleeType = edge.calleeType {
                let arrow = edge.isAsync ? "->>" : "->"
                lines.append("\(edge.callerType) \(arrow) \(calleeType) : \(edge.calleeMethod)()")
            }
        }

        lines.append("@enduml")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Mermaid

private extension SequenceScript {
    static func buildMermaidText(
        traversedEdges: [CallEdge],
        entryType: String,
        entryMethod: String
    ) -> String {
        var lines: [String] = [
            "sequenceDiagram",
            "%% title: \(entryType).\(entryMethod)"
        ]

        // Collect participants in order of first appearance
        var participants: [String] = [entryType]
        for edge in traversedEdges {
            if !edge.isUnresolved, let calleeType = edge.calleeType,
               !participants.contains(calleeType) {
                participants.append(calleeType)
            }
        }
        for participant in participants {
            lines.append("participant \(participant)")
        }

        lines.append("")

        // Emit call lines; track last resolved callee for unresolved notes
        var lastCallee = entryType
        for edge in traversedEdges {
            if edge.isUnresolved {
                lines.append("Note right of \(lastCallee): Unresolved: \(edge.calleeMethod)()")
            } else if let calleeType = edge.calleeType {
                let arrow = edge.isAsync ? "-->>" : "->>"
                lines.append("\(edge.callerType)\(arrow)\(calleeType): \(edge.calleeMethod)()")
                lastCallee = calleeType
            }
        }

        return lines.joined(separator: "\n")
    }
}

extension SequenceScript: DiagramOutputting {}
