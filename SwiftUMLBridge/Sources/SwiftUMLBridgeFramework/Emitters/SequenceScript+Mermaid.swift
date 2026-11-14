// MARK: - Mermaid

extension SequenceScript {
    static func buildMermaidText(
        traversedEdges: [CallEdge],
        entryType: String,
        entryMethod: String
    ) -> String {
        var lines: [String] = [
            "sequenceDiagram",
            "%% title: \(entryType).\(entryMethod)",
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
