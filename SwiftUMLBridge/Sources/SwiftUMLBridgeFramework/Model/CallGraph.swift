import Foundation

/// A graph of static call edges extracted from Swift source.
public struct CallGraph: Sendable {
    /// All edges in the graph.
    public let edges: [CallEdge]

    public init(edges: [CallEdge]) {
        self.edges = edges
    }

    /// Performs a depth-limited BFS from the given entry point and returns all traversed edges in order.
    ///
    /// A call is followed into the method it names as Swift reads the name after a `.`, where a
    /// keyword needs no backticks: `self.default()` into `` func `default`() `` (#130). The edge
    /// keeps the name as the call writes it, for its label.
    ///
    /// - Parameters:
    ///   - entryType: The type containing the entry method.
    ///   - entryMethod: The entry method name.
    ///   - maxDepth: Maximum call depth to traverse (default: 3).
    /// - Returns: Ordered list of `CallEdge` values reachable from the entry point.
    public func traverse(from entryType: String, entryMethod: String, maxDepth: Int) -> [CallEdge] {
        struct QueueEntry { let type: String; let method: String; let depth: Int }
        var result: [CallEdge] = []
        var visited = Set<String>()
        var queue: [QueueEntry] = [
            QueueEntry(type: entryType, method: entryMethod.canonicalMemberIdentifier, depth: 0)
        ]

        while !queue.isEmpty {
            let entry = queue.removeFirst()
            let key = "\(entry.type).\(entry.method)"
            guard !visited.contains(key), entry.depth < maxDepth else { continue }
            visited.insert(key)

            let outgoing = edges.filter { $0.callerType == entry.type && $0.callerMethod == entry.method }
            for edge in outgoing {
                result.append(edge)
                // Expand resolved edges only
                if !edge.isUnresolved, let calleeType = edge.calleeType {
                    queue.append(QueueEntry(
                        type: calleeType, method: edge.calleeMethod.canonicalMemberIdentifier, depth: entry.depth + 1
                    ))
                }
            }
        }

        return result
    }
}
