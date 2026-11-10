/// A graph of static call edges extracted from Swift source.
public struct CallGraph: Sendable {
    /// All edges in the graph.
    public let edges: [CallEdge]

    /// The bodies the edges are written in, in the order the files were read and each is written,
    /// which a call is followed into (#235). Empty for a graph made with `init(edges:)`.
    let bodies: [CallBody]

    public init(edges: [CallEdge]) {
        self.init(edges: edges, bodies: [])
    }

    init(edges: [CallEdge], bodies: [CallBody]) {
        self.edges = edges
        self.bodies = bodies
    }

    /// Performs a depth-limited BFS from the given entry point and returns all traversed edges in order.
    ///
    /// A call is followed into the method it names as Swift reads the name after a `.`, where a
    /// keyword needs no backticks: `self.default()` into `` func `default`() `` (#130). The edge
    /// keeps the name as the call writes it, for its label. Every edge filed under a name is
    /// followed, whichever body it is written in.
    ///
    /// - Parameters:
    ///   - entryType: The type containing the entry method.
    ///   - entryMethod: The entry method name.
    ///   - maxDepth: Maximum call depth to traverse (default: 3).
    /// - Returns: Ordered list of `CallEdge` values reachable from the entry point.
    public func traverse(from entryType: String, entryMethod: String, maxDepth: Int) -> [CallEdge] {
        breadthFirst(from: "\(entryType).\(entryMethod.canonicalMemberIdentifier)", maxDepth: maxDepth) { key in
            edges.filter { "\($0.callerType).\($0.callerMethod)" == key }
        } callees: { edge in
            edge.calleeType.map { ["\($0).\(edge.calleeMethod.canonicalMemberIdentifier)"] } ?? []
        }
    }

    /// The edges reachable from `entry`, each followed into the bodies its call can reach
    /// (`callees(of:)`), not every body filed under the name it calls.
    func traverse(from entry: CallBody, maxDepth: Int) -> [CallEdge] {
        var written: [String: [CallEdge]] = [:]
        for edge in edges {
            if let body = edge.callerBody { written[body, default: []].append(edge) }
        }
        var byIdentifier: [String: CallBody] = [:]
        var byName: [String: [CallBody]] = [:]
        for body in bodies {
            byIdentifier[body.identifier] = byIdentifier[body.identifier] ?? body
            byName["\(body.type).\(body.method)", default: []].append(body)
        }
        return breadthFirst(from: entry.identifier, maxDepth: maxDepth) { written[$0] ?? [] } callees: { edge in
            callees(of: edge, byIdentifier: byIdentifier, byName: byName).map(\.identifier)
        }
    }

    /// The bodies a resolved call can reach: the function local to a body it names, or else the
    /// methods filed under its type and name, of the type local to a body it calls into, or that
    /// can be named from outside a body, and of those the overloads its argument labels fit. A
    /// same-named type's method is still among them.
    private func callees(
        of edge: CallEdge, byIdentifier: [String: CallBody], byName: [String: [CallBody]]
    ) -> [CallBody] {
        if let local = edge.calleeBody { return byIdentifier[local].map { [$0] } ?? [] }
        guard let type = edge.calleeType else { return [] }
        let named = byName["\(type).\(edge.calleeMethod.canonicalMemberIdentifier)"] ?? []
        let reachable = edge.calleeLocalType.map { localType in named.filter { $0.localType == localType } }
            ?? named.filter(\.isNameable)
        return CallParameter.narrowed(reachable, to: edge.argumentLabels)
    }

    /// The edges reached from `start`, breadth first, to `maxDepth` calls deep. `outgoing` gives
    /// the edges of what a key names, and `callees` the keys a resolved edge's call is followed to.
    private func breadthFirst(
        from start: String,
        maxDepth: Int,
        outgoing: (String) -> [CallEdge],
        callees: (CallEdge) -> [String]
    ) -> [CallEdge] {
        var result: [CallEdge] = []
        var visited = Set<String>()
        var queue: [(key: String, depth: Int)] = [(start, 0)]
        while !queue.isEmpty {
            let entry = queue.removeFirst()
            guard !visited.contains(entry.key), entry.depth < maxDepth else { continue }
            visited.insert(entry.key)
            for edge in outgoing(entry.key) {
                result.append(edge)
                // Expand resolved edges only
                guard !edge.isUnresolved else { continue }
                for callee in callees(edge) { queue.append((callee, entry.depth + 1)) }
            }
        }
        return result
    }
}
