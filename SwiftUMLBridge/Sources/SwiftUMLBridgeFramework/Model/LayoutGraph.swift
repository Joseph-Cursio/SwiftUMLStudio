import Foundation

// MARK: - Layout Graph Model

/// A positioned graph produced by a layout engine, ready for SVG rendering.
public struct LayoutGraph: Sendable {
    public var nodes: [LayoutNode]
    public var edges: [LayoutEdge]

    /// Module grouping boxes, populated by the layout engine when the graph's
    /// nodes carry `module` values (i.e. the diagram was generated from a
    /// parsed SPM package). Empty for diagrams generated from loose files.
    public var clusters: [LayoutCluster] = []

    public var width: Double = 0
    public var height: Double = 0

    public init(nodes: [LayoutNode] = [], edges: [LayoutEdge] = []) {
        self.nodes = nodes
        self.edges = edges
    }
}

// MARK: - Layout Cluster

/// A module grouping box that encloses every `LayoutNode` sharing a `module`
/// value. Position and size are set by the layout engine (a compound-graph
/// parent node); renderers draw it as a tinted, labelled background rectangle.
public struct LayoutCluster: Identifiable, Sendable {
    /// The module / SPM target name — also the cluster's identity.
    public let id: String
    /// Display label (currently the module name).
    public let label: String

    /// Center X (set by layout engine)
    public var posX: Double = 0
    /// Center Y (set by layout engine)
    public var posY: Double = 0
    public var width: Double = 0
    public var height: Double = 0

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

// MARK: - Layout Node

/// A node in the layout graph with position and size set by the layout engine.
public struct LayoutNode: Identifiable, Sendable {
    public let id: String
    public let label: String
    public var stereotype: String?
    public var compartments: [NodeCompartment]

    /// Where the corresponding declaration lives in the source, when known.
    /// Populated for class-diagram nodes; `nil` for synthetic nodes (e.g. nodes
    /// derived from a `DependencyGraphModel` that has no per-node source).
    public var sourceLocation: SourceLocation?

    /// SPM target / module the type belongs to, when the diagram was generated
    /// from a parsed `SPMPackageDescription`. `nil` for diagrams generated
    /// from loose files.
    public var module: String?

    /// Center X (set by layout engine)
    public var posX: Double = 0
    /// Center Y (set by layout engine)
    public var posY: Double = 0
    public var width: Double = 0
    public var height: Double = 0

    public init(
        id: String,
        label: String,
        stereotype: String? = nil,
        compartments: [NodeCompartment] = [],
        sourceLocation: SourceLocation? = nil,
        module: String? = nil
    ) {
        self.id = id
        self.label = label
        self.stereotype = stereotype
        self.compartments = compartments
        self.sourceLocation = sourceLocation
        self.module = module
    }
}

// MARK: - Node Compartment

/// A named section within a node (e.g., properties, methods).
public struct NodeCompartment: Sendable {
    public let title: String?
    public let items: [String]

    public init(title: String? = nil, items: [String]) {
        self.title = title
        self.items = items
    }
}

// MARK: - Layout Edge

/// A directed edge between two layout nodes.
public struct LayoutEdge: Sendable {
    public let sourceId: String
    public let targetId: String
    public var label: String?
    public var style: EdgeStyle
    /// Routed points (set by layout engine)
    public var points: [LayoutPoint] = []

    public init(
        sourceId: String,
        targetId: String,
        label: String? = nil,
        style: EdgeStyle = .association
    ) {
        self.sourceId = sourceId
        self.targetId = targetId
        self.label = label
        self.style = style
    }
}

// MARK: - Edge Style

/// Visual style for an edge connection.
public enum EdgeStyle: String, Sendable {
    /// Solid line, closed triangle arrow (inheritance)
    case inheritance
    /// Dashed line, closed triangle arrow (protocol conformance)
    case realization
    /// Dashed line, open arrow (dependency / extension)
    case dependency
    /// Solid line, no arrowhead
    case association
    /// Solid line, filled diamond (composition / nesting)
    case composition
}

// MARK: - Layout Point

/// A 2D coordinate in the layout.
public struct LayoutPoint: Sendable {
    public let posX: Double
    public let posY: Double

    public init(posX: Double, posY: Double) {
        self.posX = posX
        self.posY = posY
    }
}
