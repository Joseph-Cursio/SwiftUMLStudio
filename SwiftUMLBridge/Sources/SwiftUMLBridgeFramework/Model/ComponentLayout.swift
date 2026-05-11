import Foundation

// MARK: - Positioned Component

/// A positioned `Component` in a laid-out component diagram, ready for native
/// rendering. Coordinates are in canvas-space pixels with the origin at the
/// top-left of the diagram.
public struct PositionedComponent: Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let kind: Component.Kind
    public let providedInterfaces: [String]
    public var centerX: Double
    public var centerY: Double
    public var width: Double
    public var height: Double

    public init(
        id: String,
        name: String,
        kind: Component.Kind,
        providedInterfaces: [String] = [],
        centerX: Double = 0,
        centerY: Double = 0,
        width: Double = 0,
        height: Double = 0
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.providedInterfaces = providedInterfaces
        self.centerX = centerX
        self.centerY = centerY
        self.width = width
        self.height = height
    }
}

// MARK: - Component Layout

/// Positioned layout for a component diagram. Built by `ComponentSVGRenderer`
/// when a `ComponentScript` is rendered in `.svg` format; consumed by Studio's
/// native canvas to draw with pan/zoom.
public struct ComponentLayout: Sendable {
    public var components: [PositionedComponent]
    public var dependencies: [ComponentDependency]
    public var totalWidth: Double
    public var totalHeight: Double

    public init(
        components: [PositionedComponent] = [],
        dependencies: [ComponentDependency] = [],
        totalWidth: Double = 0,
        totalHeight: Double = 0
    ) {
        self.components = components
        self.dependencies = dependencies
        self.totalWidth = totalWidth
        self.totalHeight = totalHeight
    }

    public func component(named name: String) -> PositionedComponent? {
        components.first(where: { $0.name == name })
    }
}
