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

    internal init(
        traversedEdges: [CallEdge],
        entryType: String,
        entryMethod: String,
        configuration: Configuration,
        typeLocations: [String: SourceLocation] = [:]
    ) {
        switch configuration.format {
        case .plantuml:
            self.format = .plantuml
            self.text = SequenceScript.buildPlantUMLText(
                traversedEdges: traversedEdges, entryType: entryType, entryMethod: entryMethod
            )
            self.sequenceLayout = nil
        case .mermaid, .nomnoml:
            // nomnoml does not support sequence diagrams; fall back to Mermaid
            // and report `.mermaid` so presenters hand the text to a Mermaid renderer
            self.format = .mermaid
            self.text = SequenceScript.buildMermaidText(
                traversedEdges: traversedEdges, entryType: entryType, entryMethod: entryMethod
            )
            self.sequenceLayout = nil
        case .svg:
            self.format = .svg
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

// MARK: - Shared

private extension SequenceScript {
    /// Participants in order of first appearance, starting with the entry type.
    /// Unresolved edges and edges with no callee type are ignored.
    static func orderedParticipants(entryType: String, traversedEdges: [CallEdge]) -> [String] {
        var participants: [String] = [entryType]
        for edge in traversedEdges {
            if !edge.isUnresolved, let calleeType = edge.calleeType, !participants.contains(calleeType) {
                participants.append(calleeType)
            }
        }
        return participants
    }

    /// The participant an unresolved call's note sits beside: the type that made the call (#132).
    /// A traversed edge's caller is always a participant; a hand-built one may not be, and its note
    /// goes beside the entry type, so the diagram names no participant it does not declare.
    static func noteAnchor(for edge: CallEdge, participants: [String], entryType: String) -> String {
        participants.contains(edge.callerType) ? edge.callerType : entryType
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

        let participants = orderedParticipants(entryType: entryType, traversedEdges: traversedEdges)
        for participant in participants {
            lines.append("participant \(participant)")
        }

        lines.append("")

        // Emit call lines. A note names its participant: a bare `note right:` would hang on the
        // message before it, which may be another method's.
        for edge in traversedEdges {
            if edge.isUnresolved {
                let anchor = noteAnchor(for: edge, participants: participants, entryType: entryType)
                lines.append("note right of \(anchor): Unresolved: \(edge.calleeMethod)()")
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

        let participants = orderedParticipants(entryType: entryType, traversedEdges: traversedEdges)
        for participant in participants {
            lines.append("participant \(participant)")
        }

        lines.append("")

        // Emit call lines; an unresolved call's note sits beside the type that made it
        for edge in traversedEdges {
            if edge.isUnresolved {
                let anchor = noteAnchor(for: edge, participants: participants, entryType: entryType)
                lines.append("Note right of \(anchor): Unresolved: \(edge.calleeMethod)()")
            } else if let calleeType = edge.calleeType {
                let arrow = edge.isAsync ? "-->>" : "->>"
                lines.append("\(edge.callerType)\(arrow)\(calleeType): \(edge.calleeMethod)()")
            }
        }

        return lines.joined(separator: "\n")
    }
}

extension SequenceScript: DiagramOutputting {}
