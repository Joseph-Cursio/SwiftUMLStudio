import Foundation

/// The kind of relationship a dependency edge represents.
public enum DependencyEdgeKind: String, Sendable, CaseIterable {
    case inherits
    case conforms
    case imports
}

/// A directed dependency relationship between two named nodes.
public struct DependencyEdge: Sendable, Hashable {
    /// The name of the dependent node (the node that depends on `toNode`).
    public let from: String

    /// The name of the node being depended upon.
    public let toNode: String

    /// The kind of dependency relationship.
    public let kind: DependencyEdgeKind

    /// Owning SPM module of `from`, when known. Populated by the
    /// `forPackage:` generator path; nil otherwise.
    public let fromModule: String?

    /// Owning SPM module of `toNode`, when known. Populated by the
    /// `forPackage:` generator path; nil for external/system types.
    public let toModule: String?

    public init(
        from: String,
        toNode: String,
        kind: DependencyEdgeKind,
        fromModule: String? = nil,
        toModule: String? = nil
    ) {
        self.from = from
        self.toNode = toNode
        self.kind = kind
        self.fromModule = fromModule
        self.toModule = toModule
    }
}
