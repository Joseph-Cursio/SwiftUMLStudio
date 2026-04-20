import Foundation

// MARK: - Activity Node Kind

/// The kind of node in an activity diagram.
public enum ActivityNodeKind: String, Sendable, Codable {
    /// Start of flow (filled circle).
    case start
    /// End of flow (ringed circle).
    case end
    /// An action — a call, assignment, or other sequential step.
    case action
    /// A decision — `if`/`guard`/`switch` with multiple outgoing branches.
    case decision
    /// A merge point where branches rejoin.
    case merge
    /// Fork — parallel branches begin (async let, TaskGroup).
    case fork
    /// Join — parallel branches rejoin.
    case join
    /// Start of a loop iteration (condition evaluation).
    case loopStart
    /// End of a loop body (back-edge target).
    case loopEnd
}

// MARK: - Activity Node

/// A single node in an activity graph.
public struct ActivityNode: Sendable, Identifiable, Hashable {
    public let id: Int
    public let kind: ActivityNodeKind
    public let label: String
    public let isAsync: Bool
    public let isUnresolved: Bool

    public init(
        id: Int,
        kind: ActivityNodeKind,
        label: String,
        isAsync: Bool = false,
        isUnresolved: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.isAsync = isAsync
        self.isUnresolved = isUnresolved
    }
}

// MARK: - Activity Edge

/// A directed edge connecting two activity nodes.
public struct ActivityEdge: Sendable, Hashable {
    public let fromId: Int
    public let toId: Int
    /// Optional branch label (e.g. `"true"`, `"false"`, `"case .foo"`).
    public let label: String?

    public init(fromId: Int, toId: Int, label: String? = nil) {
        self.fromId = fromId
        self.toId = toId
        self.label = label
    }
}

// MARK: - Activity Graph

/// A language-agnostic control-flow graph for a single entry function.
public struct ActivityGraph: Sendable {
    public let nodes: [ActivityNode]
    public let edges: [ActivityEdge]
    public let entryType: String
    public let entryMethod: String

    public init(
        nodes: [ActivityNode] = [],
        edges: [ActivityEdge] = [],
        entryType: String = "",
        entryMethod: String = ""
    ) {
        self.nodes = nodes
        self.edges = edges
        self.entryType = entryType
        self.entryMethod = entryMethod
    }

    /// True when the graph has no nodes (e.g. entry point not found).
    public var isEmpty: Bool { nodes.isEmpty }

    /// Returns the unique `.start` node, if any.
    public var startNode: ActivityNode? { nodes.first(where: { $0.kind == .start }) }

    /// Returns the node with the given id, or nil.
    public func node(withId identifier: Int) -> ActivityNode? {
        nodes.first(where: { $0.id == identifier })
    }

    /// Outgoing edges from the given node id.
    public func outgoingEdges(from identifier: Int) -> [ActivityEdge] {
        edges.filter { $0.fromId == identifier }
    }
}
