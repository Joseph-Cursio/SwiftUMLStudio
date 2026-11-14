// MARK: - Shared

extension SequenceScript {
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
