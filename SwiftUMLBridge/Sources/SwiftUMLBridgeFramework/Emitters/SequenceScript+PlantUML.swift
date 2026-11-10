import Foundation

// MARK: - PlantUML

extension SequenceScript {
    static func buildPlantUMLText(
        traversedEdges: [CallEdge],
        entryType: String,
        entryMethod: String
    ) -> String {
        var lines: [String] = [
            "@startuml",
            "title \(entryType).\(entryMethod)",
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
