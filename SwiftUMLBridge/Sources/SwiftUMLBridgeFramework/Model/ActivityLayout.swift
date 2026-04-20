import Foundation

// MARK: - Positioned Activity Node

/// A positioned node in a laid-out activity diagram.
public struct PositionedActivityNode: Identifiable, Sendable {
    public let id: Int
    public let kind: ActivityNodeKind
    public let label: String
    public var centerX: Double
    public var centerY: Double
    public var width: Double
    public var height: Double
    public let isAsync: Bool
    public let isUnresolved: Bool

    public init(
        id: Int,
        kind: ActivityNodeKind,
        label: String,
        centerX: Double = 0,
        centerY: Double = 0,
        width: Double = 0,
        height: Double = 0,
        isAsync: Bool = false,
        isUnresolved: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.centerX = centerX
        self.centerY = centerY
        self.width = width
        self.height = height
        self.isAsync = isAsync
        self.isUnresolved = isUnresolved
    }
}

// MARK: - Activity Layout

/// Positioned layout data for an activity diagram, ready for native rendering.
public struct ActivityLayout: Sendable {
    public var nodes: [PositionedActivityNode]
    public var edges: [ActivityEdge]
    public var title: String
    public var totalWidth: Double
    public var totalHeight: Double

    public init(
        nodes: [PositionedActivityNode] = [],
        edges: [ActivityEdge] = [],
        title: String = "",
        totalWidth: Double = 0,
        totalHeight: Double = 0
    ) {
        self.nodes = nodes
        self.edges = edges
        self.title = title
        self.totalWidth = totalWidth
        self.totalHeight = totalHeight
    }

    /// Returns positioned node by id, or nil.
    public func node(withId identifier: Int) -> PositionedActivityNode? {
        nodes.first(where: { $0.id == identifier })
    }
}
